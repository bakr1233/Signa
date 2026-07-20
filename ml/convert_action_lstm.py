"""Convert nicknochnack action.h5 -> CoreML ActionSignClassifier.mlpackage.

The model's LSTMs use activation='relu' (non-standard), so the reliable path
is a manual PyTorch reimplementation of the Keras LSTM cell with ReLU,
weight-copied and parity-checked against the original.
"""
import numpy as np
import tf_keras
import torch
import torch.nn as nn
import coremltools as ct

SEQ, FEAT = 30, 1662

orig = tf_keras.models.load_model("action.h5")
weighted = [l for l in orig.layers if l.get_weights()]
w = [l.get_weights() for l in weighted]
assert len(w) == 6  # 3 LSTM + 3 Dense


class ReluLSTM(nn.Module):
    """Keras LSTM cell with activation=relu, recurrent_activation=sigmoid."""

    def __init__(self, in_dim, units, return_sequences):
        super().__init__()
        self.units = units
        self.return_sequences = return_sequences
        self.kernel = nn.Parameter(torch.zeros(in_dim, 4 * units))
        self.recurrent = nn.Parameter(torch.zeros(units, 4 * units))
        self.bias = nn.Parameter(torch.zeros(4 * units))

    def forward(self, x):
        b, t, _ = x.shape
        h = torch.zeros(b, self.units, dtype=x.dtype)
        c = torch.zeros(b, self.units, dtype=x.dtype)
        outs = []
        for step in range(t):
            z = x[:, step, :] @ self.kernel + h @ self.recurrent + self.bias
            i, f, g, o = z.chunk(4, dim=-1)
            i = torch.sigmoid(i)
            f = torch.sigmoid(f)
            g = torch.relu(g)
            o = torch.sigmoid(o)
            c = f * c + i * g
            h = o * torch.relu(c)
            outs.append(h)
        if self.return_sequences:
            return torch.stack(outs, dim=1)
        return h


class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.l1 = ReluLSTM(FEAT, 64, True)
        self.l2 = ReluLSTM(64, 128, True)
        self.l3 = ReluLSTM(128, 64, False)
        self.d1 = nn.Linear(64, 64)
        self.d2 = nn.Linear(64, 32)
        self.d3 = nn.Linear(32, 3)

    def forward(self, x):
        x = self.l1(x)
        x = self.l2(x)
        x = self.l3(x)
        x = torch.relu(self.d1(x))
        x = torch.relu(self.d2(x))
        return torch.softmax(self.d3(x), dim=-1)


net = Net().eval()
for mod, weights in zip([net.l1, net.l2, net.l3], w[:3]):
    kernel, recurrent, bias = weights
    mod.kernel.data = torch.tensor(kernel)
    mod.recurrent.data = torch.tensor(recurrent)
    mod.bias.data = torch.tensor(bias)
for mod, weights in zip([net.d1, net.d2, net.d3], w[3:]):
    mod.weight.data = torch.tensor(weights[0].T)
    mod.bias.data = torch.tensor(weights[1])

x = (np.random.rand(4, SEQ, FEAT) * 0.8).astype(np.float32)
keras_out = orig.predict(x, verbose=0)
with torch.no_grad():
    torch_out = net(torch.tensor(x)).numpy()
diff = float(np.abs(keras_out - torch_out).max())
print("keras vs torch max diff:", diff)
assert diff < 1e-3, diff

traced = torch.jit.trace(net, torch.tensor(x[:1]))
mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="landmarks", shape=(1, SEQ, FEAT), dtype=np.float32)],
    outputs=[ct.TensorType(name="probabilities")],
    minimum_deployment_target=ct.target.iOS16,
    convert_to="mlprogram",
)
mlmodel.short_description = (
    "nicknochnack ActionDetectionforSignLanguage LSTM (hello, thanks, iloveyou). "
    "Input: 30 frames x 1662 MediaPipe Holistic values "
    "(pose 33x4, face 468x3, left hand 21x3, right hand 21x3)."
)
mlmodel.save("ActionSignClassifier.mlpackage")

m = ct.models.MLModel("ActionSignClassifier.mlpackage")
res = m.predict({"landmarks": x[:1]})
cm = res["probabilities"].flatten()
print("coreml:", np.round(cm, 4), "keras:", np.round(keras_out[0], 4))
cm_diff = float(np.abs(cm - keras_out[0]).max())
print("coreml vs keras max diff:", cm_diff)
assert cm_diff < 5e-3, cm_diff
print("OK — saved ActionSignClassifier.mlpackage")
