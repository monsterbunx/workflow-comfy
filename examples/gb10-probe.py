import json
import platform
import time
import torch
import torch.nn.functional as F

report = {
    'architecture': platform.machine(),
    'python': platform.python_version(),
    'torch': torch.__version__,
    'cuda_runtime': torch.version.cuda,
    'cuda_available': torch.cuda.is_available(),
}
assert report['cuda_available'], report
report['gpu'] = torch.cuda.get_device_name(0)
report['compute_capability'] = torch.cuda.get_device_capability(0)
report['memory_free_total_GiB'] = [round(n / 2**30, 2) for n in torch.cuda.mem_get_info()]
report['matmul'] = []
torch.manual_seed(0)
for dtype in (torch.float16, torch.bfloat16, torch.float32):
    n = 4096
    a = torch.randn(n, n, device='cuda', dtype=dtype)
    b = torch.randn(n, n, device='cuda', dtype=dtype)
    for _ in range(3):
        c = a @ b
    torch.cuda.synchronize()
    start = time.perf_counter()
    for _ in range(10):
        c = a @ b
    torch.cuda.synchronize()
    seconds = (time.perf_counter() - start) / 10
    assert torch.isfinite(c).all().item()
    report['matmul'].append({'dtype': str(dtype), 'size': n, 'ms': round(seconds * 1000, 3), 'TFLOPS': round(2*n**3 / seconds / 1e12, 3)})
    del a, b, c

q = torch.randn(1, 8, 1024, 64, device='cuda', dtype=torch.bfloat16, requires_grad=True)
y = F.scaled_dot_product_attention(q, q, q)
y.float().square().mean().backward()
torch.cuda.synchronize()
assert torch.isfinite(y).all().item() and torch.isfinite(q.grad).all().item()
report['bf16_attention_forward_backward'] = 'passed'
del q, y

buf = torch.empty(4 * 1024**3, dtype=torch.uint8, device='cuda')
buf.fill_(7)
torch.cuda.synchronize()
assert buf[0].item() == 7 and buf[-1].item() == 7
report['4_GiB_allocation_and_write'] = 'passed'
del buf
torch.cuda.empty_cache()
print(json.dumps(report, indent=2))
