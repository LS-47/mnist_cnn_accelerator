"""Train the requested 8/16/32-channel CNN without touching old checkpoints."""
import copy, csv, os, random
import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms
from cnn3_model import MNISTCNN3

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, "data")
OUT = HERE
os.makedirs(OUT, exist_ok=True)
SEED, EPOCHS, BATCH, LR = 42, 10, 128, 1e-3
random.seed(SEED); np.random.seed(SEED); torch.manual_seed(SEED)
torch.set_num_threads(1)
train = datasets.MNIST(DATA, train=True, download=False, transform=transforms.ToTensor())
test = datasets.MNIST(DATA, train=False, download=False, transform=transforms.ToTensor())
tr = DataLoader(train, batch_size=BATCH, shuffle=True, num_workers=0)
te = DataLoader(test, batch_size=BATCH, shuffle=False, num_workers=0)
model = MNISTCNN3()
opt = torch.optim.Adam(model.parameters(), lr=LR)
loss_fn = nn.CrossEntropyLoss()
best, history = -1.0, []
for epoch in range(EPOCHS):
    model.train(); seen = correct = 0; loss_sum = 0.0
    for x, y in tr:
        opt.zero_grad(); z = model(x); loss = loss_fn(z, y); loss.backward(); opt.step()
        n = y.numel(); seen += n; loss_sum += loss.item()*n; correct += (z.argmax(1)==y).sum().item()
    model.eval(); ntest = hit = 0; test_loss = 0.0
    with torch.no_grad():
        for x, y in te:
            z = model(x); ntest += y.numel(); hit += (z.argmax(1)==y).sum().item(); test_loss += loss_fn(z,y).item()*y.numel()
    acc = 100*hit/ntest
    history.append([epoch+1, loss_sum/seen, 100*correct/seen, test_loss/ntest, acc])
    print(f"epoch {epoch+1}/{EPOCHS}: train={100*correct/seen:.2f}% test={acc:.2f}%")
    if acc > best:
        best = acc
        torch.save({"model_state_dict":copy.deepcopy(model.state_dict()), "accuracy":acc,
                    "epoch":epoch+1, "architecture":"MNISTCNN3", "seed":SEED,
                    "optimizer":"Adam", "learning_rate":LR},
                   os.path.join(OUT,"mnist_cnn3_fp32.pth"))
with open(os.path.join(OUT,"cnn3_training_results.csv"),"w",newline="") as f:
    w=csv.writer(f); w.writerow(["epoch","train_loss","train_accuracy","test_loss","test_accuracy"]); w.writerows(history)
