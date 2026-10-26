#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>

static void check(cudaError_t code) {
    if (code != cudaSuccess) {
        std::fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(code));
        std::exit(1);
    }
}
__global__ void add(float *output) { output[threadIdx.x] = float(threadIdx.x) + 1.0f; }
int main() {
    float *device;
    float result[256];
    check(cudaMalloc(&device, sizeof(result)));
    add<<<1, 256>>>(device);
    check(cudaGetLastError());
    check(cudaMemcpy(result, device, sizeof(result), cudaMemcpyDeviceToHost));
    check(cudaFree(device));
    for (int i = 0; i < 256; ++i) if (result[i] != float(i) + 1.0f) return 2;
    std::puts("Native ARM64 + CUDA compilation and GPU execution: PASS");
    return 0;
}
