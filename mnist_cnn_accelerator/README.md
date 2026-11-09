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

## Program the Nexys 4 DDR

The board-level tops use the USB-UART port so a complete image can be supplied from a PC; they do not rely on manually setting 784 pixel values on switches. Connect the board's programming/UART micro-USB cable. The host sends exactly 784 unsigned grayscale bytes in row-major order at 115200 baud, 8-N-1. The FPGA sends back the predicted class as one ASCII character (`0` through `9`) and shows the class in binary on LEDs 3:0. LED 15 indicates a result has been produced, LED 14 indicates inference is running, and LED 13 indicates the image receiver is ready.

INT8 input pixels are the received byte values (0–255). INT16 converts each byte to the exported calibrated input range (0–3640) before inference. Both use the same trained checkpoint and their own exported weights. For arbitrary pictures, provide a centered 28×28 grayscale digit with a dark background and a light digit; `--invert` handles the opposite polarity.

1. Open `vivado/int8/mnist_cnn_int8.xpr` or `vivado/int16/mnist_cnn_int16.xpr` in Vivado 2026.1.
2. In the Vivado Tcl Console, set the precision and source `scripts/upgrade_vivado_project_for_board.tcl`, for example:

   ```tcl
   set CNN_PRECISION int8
   set project_dir [get_property DIRECTORY [current_project]]
   set project_root [file normalize [file join $project_dir .. ..]]
   source [file join $project_root scripts upgrade_vivado_project_for_board.tcl]
   ```

3. Confirm the project top is `nexys4ddr_int8_top` (or `nexys4ddr_int16_top`), then run **Generate Bitstream**. The script loads the 100 MHz Nexys clock constraint, board pin assignments, UART/board RTL, clock wizard and precision-specific weight memories.
4. Program the board with the resulting `.bit` file using Hardware Manager. In Windows Device Manager, find the board's USB Serial Port COM number.
5. Install host dependencies and classify an image:

   ```powershell
   python -m pip install -r requirements-hardware.txt
   python python/uart_infer.py --port COM5 --image path\to\digit.png
   ```

   Replace `COM5` and the image path as needed. The LED class and serial reply should show a digit after the image is sent.

   To measure real FPGA accuracy on the first 100 official MNIST test images, run `python python/uart_benchmark.py --port COM5 --count 100`. It prints each FPGA prediction beside the true label and reports the measured accuracy.

The board wrappers use a 10 MHz Clocking Wizard output for the CNN core and UART. Actual timing closure, resource use, and bitstream generation must be confirmed by the Vivado implementation run; this workspace does not contain a runnable Vivado command-line executable. A batch build is available from the accelerator directory with `vivado -mode batch -source scripts/build_board_bitstream.tcl -tclargs int8` (or `int16`).

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

This creates `vivado/int8/mnist_cnn_int8.xpr`, targeting `xc7a100tcsg324-1`. Use `source scripts/setup_vivado_int16.tcl` for the separate INT16 project. In each project, run **Run Behavioral Simulation**. The Tcl batch command in `scripts/run_synthesis.tcl` generates synthesis utilization and timing reports after the corresponding project exists.

The setup targets the XC7A100T part but does not assume a board pinout. Run synthesis separately for INT8 and INT16; both configurations do not run simultaneously. Vivado synthesis and the resulting LUT, DSP, BRAM, and timing comparison are still to be generated.

## Re-export parameters

Run `python python/export_int8.py` or `python python/export_int16.py` from this folder. The scripts reload the included checkpoint and local MNIST IDX files, regenerate weight/bias/multiplier memories and the first 100 test vectors, and write accuracy/quantization reports. INT16 uses separate activation calibration and reports its INT32 overflow measurements in `weights/int16/quantization_metadata.json`.
