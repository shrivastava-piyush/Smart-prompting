#!/usr/bin/env python3
"""
One-time build: convert sentence-transformers/all-MiniLM-L6-v2 to a CoreML
.mlpackage so the Swift app can run embeddings on the Neural Engine on both
macOS and iOS. Commit the output at Resources/MiniLM.mlpackage.

Usage:
    python3 scripts/build-coreml.py

Requires: coremltools, torch, transformers (install into a local venv).
"""
from __future__ import annotations

import sys
from pathlib import Path

MODEL_ID = "sentence-transformers/all-MiniLM-L6-v2"
OUT = Path(__file__).resolve().parent.parent / "Resources" / "MiniLM.mlpackage"


def main() -> int:
    try:
        import coremltools as ct
        import torch
        from transformers import AutoModel, AutoTokenizer
    except ImportError as e:
        print(f"missing dependency: {e}", file=sys.stderr)
        print("install: pip install coremltools torch transformers", file=sys.stderr)
        return 2

    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModel.from_pretrained(MODEL_ID).eval()

    class MeanPooled(torch.nn.Module):
        def __init__(self, backbone):
            super().__init__()
            self.backbone = backbone

        def forward(self, input_ids, attention_mask):
            out = self.backbone(input_ids=input_ids, attention_mask=attention_mask)
            token_emb = out.last_hidden_state
            mask = attention_mask.unsqueeze(-1).float()
            summed = (token_emb * mask).sum(dim=1)
            counts = mask.sum(dim=1).clamp(min=1e-9)
            pooled = summed / counts
            # L2 normalize so cosine == dot
            return torch.nn.functional.normalize(pooled, p=2, dim=1)

    wrapped = MeanPooled(model).eval()

    sample = tokenizer("hello world", return_tensors="pt", padding="max_length",
                       truncation=True, max_length=128)
    traced = torch.jit.trace(
        wrapped, (sample["input_ids"], sample["attention_mask"])
    )

    ml = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, 128), dtype=int),
            ct.TensorType(name="attention_mask", shape=(1, 128), dtype=int),
        ],
        convert_to="mlprogram",
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS16,
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    ml.save(str(OUT))
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
