import numpy as np

# Create random 8-bit integers
N = 4
A = np.random.randint(-128, 127, (N, N), dtype=np.int8)
B = np.random.randint(-128, 127, (N, N), dtype=np.int8)

result = np.matmul(A.astype(np.int32), B.astype(np.int32))

# Save for Verilog in hex
np.savetxt("matrix_a.hex", A.flatten(), fmt='%02x')
np.savetxt("gold_result.hex", result.flatten(), fmt='%08x')