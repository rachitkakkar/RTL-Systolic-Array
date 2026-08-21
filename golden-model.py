# import random

N = 8 # must match RTL parameters
# random.seed(42) # make deterministic

# # Random 8-bit matricies
# A = [[random.randint(-128, 127) for _ in range(N)] for _ in range(N)]
# B = [[random.randint(-128, 127) for _ in range(N)] for _ in range(N)]

# # Compute golden result
# result = [[0]*N for _ in range(N)]
# for i in range(N):
#     for j in range(N):
#         for k in range(N):
#             result[i][j] += A[i][k] * B[k][j]

import numpy as np

rng = np.random.default_rng(42)

# Deterministic random 8-bit matrices
A = rng.integers(-128, 128, size=(N, N), dtype=np.int8)
B = rng.integers(-128, 128, size=(N, N), dtype=np.int8)

# Compute result
result = A.astype(np.int32) @ B.astype(np.int32)

# Save for Verilog $readmemh (one value per line, row-major order)
with open("matrix_a.hex", "w") as f:
    # for row in A:
    #     for val in row:
    #         f.write(f"{val & 0xFF:02x}\n")
    for val in A.flat:
        f.write(f"{int(val) & 0xFF:02x}\n")

with open("matrix_b.hex", "w") as f:
    # for row in B:
    #     for val in row:
    #         f.write(f"{val & 0xFF:02x}\n")
    for val in B.flat:
        f.write(f"{int(val) & 0xFF:02x}\n")

with open("gold_result.hex", "w") as f:
    # for row in result:
    #     for val in row:
    #         f.write(f"{val & 0xFFFF:04x}\n")
    for val in result.flat:
        f.write(f"{int(val) & 0xFFFF:04x}\n")

print(f"Generated {N}x{N} test vectors.")
print("Matrix A:")
for row in A:
    print("  ", row)
print("Matrix B:")
for row in B:
    print("  ", row)
print("Expected C = A*B:")
for row in result:
    print("  ", row)