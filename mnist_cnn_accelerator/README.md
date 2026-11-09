# MNIST CNN accelerator: INT8 and INT16

Standalone implementation of the supplied three-convolution MNIST architecture. It uses the included trained FP32 checkpoint and separate INT8 and INT16 parameter exports. The earlier GitHub clone and the original Vivado project are not dependencies of this folder.

## Model and software baseline

The checkpoint at `python/mnist_cnn3_fp32.pth` was trained with the included `python/cnn3_model.py`. Its architecture is Conv(1→8, 3×3), ReLU, 2×2 max-pool; Conv(8→16, 3×3), ReLU, max-pool; Conv(16→32, 3×3), ReLU, max-pool; FC(32→16), ReLU; FC(16→10), argmax. Convolutions use valid padding and stride 1; pooling uses stride 2. The included IDX data supports re-exporting parameters and test vectors.

Recorded full-test-set results from this checkpoint:

| Model | Correct | Accuracy |
|---|---:|---:|
| FP32 PyTorch baseline | 9,752 / 10,000 | 97.52% |
| INT8 Python reference | 9,757 / 10,000 | 97.57% |
| INT16 Python reference | 9,754 / 10,000 | 97.54% |

INT8 and INT16 exports are both derived from the same FP32 checkpoint. The INT8 exporter uses symmetric signed weights, unsigned 8-bit ReLU activations, Q31 requantization, and INT32 accumulation. The INT16 exporter uses signed 16-bit weights and unsigned 16-bit activation storage. To keep INT32 sums in range, it caps the calibrated activation codes by layer (input 3640, then 455, 227, 1023, and 2047 into the successive MAC stages). Its metadata records bias bounds and observed maximum accumulators; the largest observed INT16 absolute accumulator over the full test set is 515,770,772, within signed INT32.

## RTL and testbenches

- `rtl/int8/cnn_int8_top.v` and `rtl/int16/cnn_int16_top.v` are the complete precision-specific inference tops.
- Separate modules implement the input buffer, shared MAC datapath, Q31 requantizer, ReLU clamp, 2×2 max-pool, and argmax comparison in each precision folder. The top integrates the weight/bias memories, feature-map buffers, convolution and FC sequences, and FSM controller. It processes one image at a time and accepts 784 streamed pixels when `ready` is high.
- `tb/tb_cnn_int8.v` and `tb/tb_cnn_int16.v` feed the first 100 MNIST test images and compare the RTL class against the matching bit-accurate Python prediction. These expected values check hardware/reference agreement; they are not ground-truth labels. `tb/data/mnist100_labels.mem` contains the actual labels. Each image prints the RTL result, Python result, and true MNIST label.
- Before extracting the arithmetic blocks into separate modules, both complete FSM tops passed all 100 images in Icarus Verilog. After module extraction, both precision builds compile and the current module-based tops pass the first MNIST image in simulation. The updated 100-image run is left for the Vivado project/testbench workflow.

Each inference core processes one image at a time. Its controller now tracks spatial and kernel coordinates with counters instead of synthesizing variable divide/modulo arithmetic. The Q31 requantizer uses the actual 24-bit positive multiplier range from the exported model instead of a 64-bit multiplier input.

## Target board and clock

The active board target is the Xilinx ZC702 evaluation board with an XC7Z020-1CLG484C SoC (`xc7z020clg484-1` in Vivado). The board's system oscillator is a 200 MHz differential LVDS clock. The ZC702 clock module uses the 7-series MMCM to generate the 10 MHz clock used by the CNN core and UART. To convert the existing INT8 project in place, open `vivado/int8/mnist_cnn_int8.xpr` and source `scripts/upgrade_existing_int8_to_zc702.tcl` in the Vivado Tcl Console. The legacy `vivado/int16` and the old Nexys top/constraints are preserved separately.

## ZC702 UART connection

The ZC702's onboard USB-UART bridge is connected to the Zynq processing system, not directly to programmable-logic pins. These pure-RTL CNN projects use a separate external USB-UART adapter on GPIO header J62 instead. Use a 2.5 V-compatible adapter or a suitable level shifter. Connect adapter TX to J62 pin 3 (PMOD2_2, FPGA RX), adapter RX to J62 pin 4 (PMOD2_3, FPGA TX), and connect grounds. Do not connect the adapter's VCC pin. These two PMOD signals are also wired to LEDs DS16 and DS15, so those LEDs may flicker during serial traffic.

The host sends 784 unsigned grayscale bytes in row-major order at 115200 baud, 8-N-1. The FPGA returns one ASCII digit (`0` through `9`). INT8 uses the received bytes directly; INT16 maps each byte to the calibrated input range 0–3640. For arbitrary images, supply a centered 28×28 grayscale digit with a dark background and a light digit; use `--invert` for the opposite polarity.

## Build and run on the ZC702

In Vivado 2026.1, open the existing INT8 project and run this from the Tcl Console:

```tcl
source {C:/.../mnist_cnn_accelerator/scripts/upgrade_existing_int8_to_zc702.tcl}
```

The script updates the existing project to `xc7z020clg484-1`, selects `zc702_int8_top`, replaces Nexys constraints with the ZC702 XDC, and replaces the locked legacy clock IP with the ZC702 MMCM RTL module. It does not launch synthesis or implementation. Run those steps yourself after confirming the top and XDC.

Install the host dependencies and classify an image using the external adapter's COM port:

```powershell
python -m pip install -r requirements-hardware.txt
python python/uart_infer.py --port COM5 --image path\to\digit.png
```

Replace `COM5` and the image path as needed. For a 100-image hardware accuracy run, use `python python/uart_benchmark.py --port COM5 --count 100`; it reports each FPGA prediction beside the true MNIST label.

The supplied board target and XDC are prepared for the ZC702, but synthesis, timing closure, bitstream generation, and physical board inference must still be confirmed by running Vivado on the board.

## Run the simulations with Icarus Verilog

From this folder:

```powershell
iverilog -g2012 -o sim_int8.vvp rtl/int8/*.v tb/tb_cnn_int8.v
vvp sim_int8.vvp

iverilog -g2012 -o sim_int16.vvp rtl/int16/*.v tb/tb_cnn_int16.v
vvp sim_int16.vvp
```

Both simulations read their weight and pixel memories by absolute path under this project folder. If you move the folder, update those paths in the RTL tops and testbenches.

For batch use after setup, run `vivado -mode batch -source scripts/run_simulation.tcl -tclargs int8` or replace `int8` with `int16`.

## Create separate Vivado projects

Open Vivado's Tcl Console, change to this folder, then source one setup script:

```tcl
cd path/to/mnist_cnn_accelerator
source scripts/setup_vivado_int8.tcl
```

These legacy setup scripts create Nexys 4 DDR projects targeting `xc7a100tcsg324-1`. For the selected ZC702 board, convert the existing INT8 project with `scripts/upgrade_existing_int8_to_zc702.tcl`.

The setup targets the XC7A100T part but does not assume a board pinout. Run synthesis separately for INT8 and INT16; both configurations do not run simultaneously. Vivado synthesis and the resulting LUT, DSP, BRAM, and timing comparison are still to be generated.

## Re-export parameters

Run `python python/export_int8.py` or `python python/export_int16.py` from this folder. The scripts reload the included checkpoint and local MNIST IDX files, regenerate weight/bias/multiplier memories and the first 100 test vectors, and write accuracy/quantization reports. INT16 uses separate activation calibration and reports its INT32 overflow measurements in `weights/int16/quantization_metadata.json`.
