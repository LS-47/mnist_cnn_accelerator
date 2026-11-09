"""Run a real MNIST test-set accuracy check against the programmed FPGA."""
import argparse
import os
import struct

import numpy as np
import serial

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MNIST_RAW = os.path.join(ROOT, "data", "MNIST", "raw")


def read_idx():
    image_path = os.path.join(MNIST_RAW, "t10k-images-idx3-ubyte")
    label_path = os.path.join(MNIST_RAW, "t10k-labels-idx1-ubyte")
    with open(image_path, "rb") as stream:
        magic, count, rows, cols = struct.unpack(">IIII", stream.read(16))
        if magic != 2051 or rows != 28 or cols != 28:
            raise ValueError("Unexpected MNIST image IDX file")
        images = np.frombuffer(stream.read(), dtype=np.uint8).reshape(count, 28, 28)
    with open(label_path, "rb") as stream:
        magic, label_count = struct.unpack(">II", stream.read(8))
        if magic != 2049 or label_count != count:
            raise ValueError("Unexpected MNIST label IDX file")
        labels = np.frombuffer(stream.read(), dtype=np.uint8)
    return images, labels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="Windows COM port, e.g. COM5")
    parser.add_argument("--count", type=int, default=100, help="number of first test images (1..10000)")
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()
    images, labels = read_idx()
    count = min(max(args.count, 1), len(labels))
    correct = 0

    try:
        with serial.Serial(args.port, args.baud, timeout=30, write_timeout=10) as port:
            port.reset_input_buffer()
            for index in range(count):
                port.write(images[index].tobytes())
                port.flush()
                reply = port.read(1)
                if reply not in b"0123456789":
                    raise RuntimeError(f"No valid FPGA class for image {index}; received {reply!r}")
                prediction = int(reply.decode("ascii"))
                label = int(labels[index])
                correct += prediction == label
                print(f"{index + 1:4d}/{count}: FPGA={prediction} label={label} "
                      f"{'OK' if prediction == label else 'MISS'}")
    except serial.SerialException as exc:
        raise SystemExit(f"Serial error: {exc}") from exc

    print(f"FPGA accuracy: {correct}/{count} = {100.0 * correct / count:.2f}%")


if __name__ == "__main__":
    main()
