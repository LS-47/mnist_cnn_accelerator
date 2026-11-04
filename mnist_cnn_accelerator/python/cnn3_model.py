"""Three-convolution MNIST model used for the XC7A100T design."""
import torch.nn as nn


class MNISTCNN3(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 8, 3, padding=0)
        self.conv2 = nn.Conv2d(8, 16, 3, padding=0)
        self.conv3 = nn.Conv2d(16, 32, 3, padding=0)
        self.fc1 = nn.Linear(32, 16)
        self.fc2 = nn.Linear(16, 10)

    def forward(self, x):
        x = nn.functional.max_pool2d(nn.functional.relu(self.conv1(x)), 2, 2)
        x = nn.functional.max_pool2d(nn.functional.relu(self.conv2(x)), 2, 2)
        x = nn.functional.max_pool2d(nn.functional.relu(self.conv3(x)), 2, 2)
        x = x.flatten(1)
        x = nn.functional.relu(self.fc1(x))
        return self.fc2(x)
