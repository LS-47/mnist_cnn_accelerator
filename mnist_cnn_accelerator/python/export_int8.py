"""Symmetric INT8 export and bit-accurate CPU reference for MNISTCNN3."""
import json, os, sys, time
import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader
from torchvision import datasets, transforms
HERE=os.path.dirname(os.path.abspath(__file__))
ROOT=os.path.dirname(HERE)
sys.path.insert(0, HERE)
from cnn3_model import MNISTCNN3
MODEL=os.path.join(HERE,"mnist_cnn3_fp32.pth")
DATA=os.path.join(ROOT,"data")
OUT=os.path.join(ROOT,"weights","int8")
os.makedirs(OUT,exist_ok=True)
torch.set_num_threads(1)
net=MNISTCNN3().eval()
ckpt=torch.load(MODEL,map_location="cpu",weights_only=True)
net.load_state_dict(ckpt["model_state_dict"])
train=datasets.MNIST(DATA,train=True,download=False,transform=transforms.ToTensor())
test=datasets.MNIST(DATA,train=False,download=False,transform=transforms.ToTensor())
EVAL_COUNT=int(os.environ.get("MNIST_EVAL_COUNT",str(len(test))))

# Calibrate unsigned post-ReLU activations. Input bytes represent ToTensor() * 255.
mx={k:0.0 for k in ("conv1","pool1","conv2","pool2","conv3","pool3","fc1")}
with torch.no_grad():
    for i in range(0,1000,100):
        x=torch.stack([train[j][0] for j in range(i,min(i+100,1000))])
        a=F.relu(net.conv1(x)); mx["conv1"]=max(mx["conv1"],a.max().item())
        a=F.max_pool2d(a,2); mx["pool1"]=max(mx["pool1"],a.max().item())
        a=F.relu(net.conv2(a)); mx["conv2"]=max(mx["conv2"],a.max().item())
        a=F.max_pool2d(a,2); mx["pool2"]=max(mx["pool2"],a.max().item())
        a=F.relu(net.conv3(a)); mx["conv3"]=max(mx["conv3"],a.max().item())
        a=F.max_pool2d(a,2); mx["pool3"]=max(mx["pool3"],a.max().item())
        a=F.relu(net.fc1(a.flatten(1))); mx["fc1"]=max(mx["fc1"],a.max().item())
# Pooling selects an existing quantized value, so it keeps its input scale.
mx["pool1"]=mx["conv1"]; mx["pool2"]=mx["conv2"]; mx["pool3"]=mx["conv3"]
act_scale={"input":1.0/255.0,**{k:(v/255.0 if v else 1.0) for k,v in mx.items()}}
layers={"conv1":net.conv1,"conv2":net.conv2,"conv3":net.conv3,"fc1":net.fc1,"fc2":net.fc2}
q={}; metadata={"scheme":"symmetric signed INT8 weights, unsigned affine-free ReLU activations [0,255]",
 "rounding":"nearest-even (NumPy/PyTorch round)","saturation":"weights [-127,127], activations [0,255], accumulators signed INT32",
 "input_scale":act_scale["input"],"activation_scales":act_scale,"calibration_images":1000,
 "final_layer":"FC2 class scores remain INT32 accumulators; argmax is invariant to a common positive scale","layers":{}}
for name,layer in layers.items():
    wf=layer.weight.detach().numpy(); ws=float(np.max(np.abs(wf))/127.0) or 1.0
    qw=np.clip(np.rint(wf/ws),-127,127).astype(np.int8)
    src="input" if name=="conv1" else {"conv2":"pool1","conv3":"pool2","fc1":"pool3","fc2":"fc1"}[name]
    dst=None if name=="fc2" else {"conv1":"conv1","conv2":"conv2","conv3":"conv3","fc1":"fc1"}[name]
    si=act_scale[src]; so=1.0 if dst is None else act_scale[dst]
    bias=np.rint(layer.bias.detach().numpy()/(si*ws)).astype(np.int64)
    ratio=si*ws/so
    multiplier=int(np.rint(ratio*(1<<31)))
    if not 0 <= multiplier < (1 << 24):
        raise OverflowError(f"Q31 multiplier does not fit the 24-bit RTL port in {name}: {multiplier}")
    q[name]=(qw,bias,multiplier)
    flat=qw.reshape(-1)
    np.savetxt(os.path.join(OUT,name+"_weight.txt"),flat.astype(np.int16),fmt="%d")
    np.savetxt(os.path.join(OUT,name+"_weight.mem"),flat.view(np.uint8),fmt="%02x")
    np.savetxt(os.path.join(OUT,name+"_bias.txt"),bias,fmt="%d")
    np.savetxt(os.path.join(OUT,name+"_bias.mem"),
               (bias & 0xffffffff),fmt="%08x")
    if name != "fc2":
        np.savetxt(os.path.join(OUT,name+"_multiplier.mem"),
                   np.array([multiplier],dtype=np.int64),fmt="%016x")
    # Worst case for any signed partial-sum order: maximum unsigned activation
    # code times each output row's L1 weight norm, plus the absolute bias.
    row_l1=np.abs(qw.reshape(qw.shape[0],-1).astype(np.int64)).sum(axis=1)
    acc_bound=int(np.max(row_l1)*255+np.max(np.abs(bias)))
    if acc_bound > (1<<31)-1:
        raise OverflowError(f"INT32 worst-case accumulator bound exceeded in {name}: {acc_bound}")
    metadata["layers"][name]={"weight_scale":ws,"input_scale":si,"output_scale":so,"requant_multiplier_q31":multiplier,
      "bias_scale":si*ws,"weight_shape":list(qw.shape),"bias_scale_rule":"input_scale * weight_scale",
      "int32_worst_case_accumulator_bound":acc_bound}
json.dump(metadata,open(os.path.join(OUT,"quantization_metadata.json"),"w"),indent=2)

def requant(acc,mult):
    # Integer round-to-nearest-even at Q31, including negative accumulators.
    p=acc.astype(np.int64)*np.int64(mult); den=1<<31
    lo=np.floor_divide(p,den); rem=np.mod(p,den); half=den//2
    return lo+((rem>half)|((rem==half)&((lo&1)!=0))).astype(np.int64)

def qconv(x,w,b,mult,activate=True):
    # x: N,C,H,W uint8; w: O,C,3,3 int8. int64 dot products avoid host overflow.
    n,ci,h,ww=x.shape; co=w.shape[0]; oh=h-2; ow=ww-2
    out=np.empty((n,co,oh,ow),np.uint8 if activate else np.int32)
    for yy in range(oh):
      for xx in range(ow):
        patch=x[:,:,yy:yy+3,xx:xx+3].reshape(n,-1).astype(np.int64)
        acc=patch @ w.reshape(co,-1).astype(np.int64).T + b
        z=requant(acc,mult)
        if activate: z=np.clip(z,0,255).astype(np.uint8)
        out[:,:,yy,xx]=z
    return out

def qfc(x,w,b,mult,activate=True):
    acc=x.astype(np.int64) @ w.astype(np.int64).T+b
    if not activate: return acc
    z=requant(acc,mult)
    return np.clip(z,0,255).astype(np.uint8)

def infer(image):
    x=np.rint(image.numpy().reshape(1,1,28,28)*255).astype(np.uint8)
    w,b,m=q["conv1"]; x=qconv(x,w,b,m); x=x.reshape(1,8,13,2,13,2).max(axis=(3,5))
    w,b,m=q["conv2"]; x=qconv(x,w,b,m)[:,:,:10,:10]; x=x.reshape(1,16,5,2,5,2).max(axis=(3,5))
    w,b,m=q["conv3"]; x=qconv(x,w,b,m)[:,:,:2,:2]; x=x.reshape(1,32,1,2,1,2).max(axis=(3,5))
    x=x.reshape(1,32); w,b,m=q["fc1"]; x=qfc(x,w,b,m)
    w,b,m=q["fc2"]; return int(qfc(x,w,b,m,False).argmax(axis=1)[0])

fp32_correct=0; fp32_total=0; fp32_start=time.perf_counter()
with torch.no_grad():
    for images,labels in DataLoader(test,batch_size=128,shuffle=False,num_workers=0):
        fp32_correct += (net(images).argmax(1)==labels).sum().item()
        fp32_total += labels.numel()
fp32_elapsed=time.perf_counter()-fp32_start

correct=0; start=time.perf_counter(); pixel_stream=[]; expected=[]
for i in range(EVAL_COUNT):
    image,label=test[i]
    pred=infer(image); correct += pred==label
    if i<100:
        expected.append(pred)
        pixel_stream.extend(np.rint(image.numpy().reshape(-1)*255).astype(np.uint8).tolist())
elapsed=time.perf_counter()-start
print(f"FP32 baseline: {fp32_correct}/{fp32_total} = {100*fp32_correct/fp32_total:.2f}%")
print(f"Bit-accurate INT8 reference: {correct}/{EVAL_COUNT} = {100*correct/EVAL_COUNT:.2f}%")
print(f"CPU INT8 reference time: {elapsed/EVAL_COUNT*1000:.3f} ms/image (not FPGA latency)")
print("Weights and metadata:",OUT)
report_dir=os.path.join(ROOT,"reports"); os.makedirs(report_dir,exist_ok=True)
json.dump({"architecture":"MNISTCNN3","fp32":{"correct":fp32_correct,"total":fp32_total,
          "accuracy_percent":100*fp32_correct/fp32_total,"cpu_ms_per_image":1000*fp32_elapsed/fp32_total},
          "int8_reference":{"correct":int(correct),"total":EVAL_COUNT,
          "accuracy_percent":100*correct/EVAL_COUNT,"cpu_ms_per_image":1000*elapsed/EVAL_COUNT},
          "rtl_python_argmax_agreement":None},
          open(os.path.join(report_dir,"accuracy_int8.json"),"w"),indent=2)
tbdir=os.path.join(ROOT,"tb","data"); os.makedirs(tbdir,exist_ok=True)
np.savetxt(os.path.join(tbdir,"mnist100_pixels_int8.mem"),np.asarray(pixel_stream,dtype=np.uint8),fmt="%02x")
np.savetxt(os.path.join(tbdir,"mnist100_expected_int8.mem"),np.asarray(expected,dtype=np.uint8),fmt="%x")
np.savetxt(os.path.join(tbdir,"mnist100_labels.mem"),
           np.asarray([test[i][1] for i in range(min(100,EVAL_COUNT))],dtype=np.uint8),fmt="%x")
