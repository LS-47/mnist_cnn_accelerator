"""Send one 28x28 grayscale image to the Nexys 4 DDR CNN over USB-UART."""
import argparse
import sys

try:
    import serial
    from PIL import Image, ImageOps
except ImportError as exc:
    raise SystemExit("Install requirements with: python -m pip install pyserial pillow") from exc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="Windows COM port, e.g. COM5")
    parser.add_argument("--image", required=True, help="PNG/JPG image to classify")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--invert", action="store_true",
                        help="invert grayscale if your image has a white background")
    args = parser.parse_args()

    image = Image.open(args.image).convert("L")
    if args.invert:
        image = ImageOps.invert(image)
    image = image.resize((28, 28), Image.Resampling.LANCZOS)
    payload = image.tobytes()
    if len(payload) != 784:
        raise SystemExit("Expected 784 pixel bytes after 28x28 resize")

    try:
        with serial.Serial(args.port, args.baud, timeout=30, write_timeout=10) as port:
            port.reset_input_buffer()
            port.write(payload)
            port.flush()
            answer = port.read(1)
    except serial.SerialException as exc:
        raise SystemExit(f"Serial error: {exc}") from exc

    if not answer:
        raise SystemExit("No result received. Check COM port, board reset, and bitstream.")
    if answer not in b"0123456789":
        raise SystemExit(f"Unexpected FPGA reply: {answer!r}")
    print(f"FPGA prediction: {answer.decode('ascii')}")


if __name__ == "__main__":
    main()
