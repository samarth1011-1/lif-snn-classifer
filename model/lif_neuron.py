"""
Bit-accurate Python model of the LIF SNN Pattern Detector.
Matches the Verilog RTL:
  - Parallel: lif_neuron.v, weight_mac.v, spike_counter.v, snn_top_parallel.v
  - TDM:      weight_mac.v, snn_top_tdm.v
"""

# Stored 5x5 templates for digits 0 to 3 (row-major, MSB = top-left)
TEMPLATES = [
    0b01110_10001_10001_10001_01110,  # "0"
    0b00100_01100_00100_00100_01110,  # "1"
    0b01110_00001_01110_10000_11111,  # "2"
    0b01110_00001_01110_00001_01110   # "3"
]


def sat_add(a, b):
    """16-bit unsigned saturating add."""
    return min(a + b, 0xFFFF)


class LIFNeuron:
    """Models rtl/lif_neuron.v bit-for-bit."""

    def __init__(self, v_th=384, k=5):
        self.v_th = v_th
        self.k = k
        self.v_mem = 0

    def reset(self):
        self.v_mem = 0

    def step(self, i_input):
        # Round-up leak: ceil(v_mem / 2^K) = (v_mem + 2^K - 1) >> K
        leak = (self.v_mem + (1 << self.k) - 1) >> self.k
        decayed = self.v_mem - leak
        v_next = sat_add(decayed, i_input)

        if v_next >= self.v_th:
            spike = 1
            self.v_mem = 0
        else:
            spike = 0
            self.v_mem = v_next

        return spike


def compute_mac(pattern, template, w_on=16, w_off=-32):
    """Models rtl/weight_mac.v: dot product of input spikes and template weights."""
    acc = 0
    for i in range(25):
        if (pattern >> i) & 1:
            w = w_on if ((template >> i) & 1) else w_off
            acc += w
    # Clamping: negative -> 0, max -> 0xFFFF
    return max(0, min(acc, 0xFFFF))


class SNNClassifier:
    """Models snn_top_parallel.v: 4 parallel neurons + spike counter + argmax."""

    def __init__(self, v_th=384, k=5, window_len=64, w_on=16, w_off=-32):
        self.v_th = v_th
        self.k = k
        self.window_len = window_len
        self.w_on = w_on
        self.w_off = w_off
        self.neurons = [LIFNeuron(v_th=v_th, k=k) for _ in range(4)]

    def classify(self, pattern, warmup_cycles=2):
        currents = [
            compute_mac(pattern, tmpl, self.w_on, self.w_off)
            for tmpl in TEMPLATES
        ]

        for n in self.neurons:
            n.reset()

        for _ in range(warmup_cycles):
            for i, n in enumerate(self.neurons):
                n.step(currents[i])

        counts = [0, 0, 0, 0]
        for _ in range(self.window_len):
            for i, n in enumerate(self.neurons):
                counts[i] += n.step(currents[i])

        predicted = 0
        max_c = 0
        for i, c in enumerate(counts):
            if c > max_c:
                max_c = c
                predicted = i

        return {
            "currents": currents,
            "counts": counts,
            "predicted": predicted,
            "rejected": (max(counts) == 0)
        }


class SNNClassifierTDM:
    """Models snn_top_tdm.v: 1 shared MAC + 1 shared LIF core evaluating classes round-robin."""

    def __init__(self, v_th=384, k=5, window_len=64, w_on=16, w_off=-32, num_classes=4):
        self.v_th = v_th
        self.k = k
        self.window_len = window_len
        self.w_on = w_on
        self.w_off = w_off
        self.num_classes = num_classes

    def classify(self, pattern):
        currents = [
            compute_mac(pattern, TEMPLATES[c], self.w_on, self.w_off)
            for c in range(self.num_classes)
        ]

        vmem_state = [0] * self.num_classes
        spike_counts = [0] * self.num_classes

        # 256 clock cycles (round-robin: 1 neuron per cycle)
        for _ in range(self.window_len):
            for c in range(self.num_classes):
                v_mem = vmem_state[c]
                leak = (v_mem + (1 << self.k) - 1) >> self.k
                decayed = v_mem - leak
                v_next = sat_add(decayed, currents[c])

                if v_next >= self.v_th:
                    spike_counts[c] += 1
                    vmem_state[c] = 0
                else:
                    vmem_state[c] = v_next

        predicted = 0
        max_c = 0
        for i, cnt in enumerate(spike_counts):
            if cnt > max_c:
                max_c = cnt
                predicted = i

        return {
            "currents": currents,
            "counts": spike_counts,
            "predicted": predicted,
            "rejected": (max(spike_counts) == 0)
        }


def print_pattern(pat):
    for r in range(4, -1, -1):
        row_bits = (pat >> (r * 5)) & 0x1F
        chars = ["#" if (row_bits >> (4 - c)) & 1 else "." for c in range(5)]
        print("  " + "".join(chars))


def run_tests():
    classifier_par = SNNClassifier(v_th=384, k=5, window_len=64)
    classifier_tdm = SNNClassifierTDM(v_th=384, k=5, window_len=64)

    test_cases = [
        ("Digit 0", TEMPLATES[0], 0),
        ("Digit 1", TEMPLATES[1], 1),
        ("Digit 2", TEMPLATES[2], 2),
        ("Digit 3", TEMPLATES[3], 3),
        ("Noisy Digit 2", TEMPLATES[2] ^ ((1 << 24) | (1 << 0)), 2),
        ("All Ones (Reject)", (1 << 25) - 1, None),
    ]

    print("=" * 65)
    print(" SNN Python Model Test Suite: Parallel vs TDM")
    print("=" * 65)

    for name, pat, expected in test_cases:
        res_par = classifier_par.classify(pat)
        res_tdm = classifier_tdm.classify(pat)

        print(f"\n{name}:")
        print_pattern(pat)
        print(f"  Parallel Spikes: {res_par['counts']} -> Class {res_par['predicted']}")
        print(f"  TDM Spikes:      {res_tdm['counts']} -> Class {res_tdm['predicted']}")

        if expected is None:
            match = res_par["rejected"] and res_tdm["rejected"]
            status = "PASS (both rejected)" if match else "FAIL"
        else:
            match = (res_par["predicted"] == expected) and (res_tdm["predicted"] == expected)
            status = f"PASS (both match expected {expected})" if match else "FAIL"

        print(f"  Verification:    {status}")

    print("\n" + "=" * 65)


if __name__ == "__main__":
    run_tests()
