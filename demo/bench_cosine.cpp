/**
 * Offline benchmark for the production workload:
 * IVF256,Flat with METRIC_INNER_PRODUCT, 672-dimensional L2-normalized vectors.
 *
 * Reports QPS and latency percentiles (p50, p95, p99) across 8 rounds of
 * 128-query batches. Accepts --nprobe N for tuning without recompilation.
 *
 * Not CI-gated; intended for offline speed comparison across platforms.
 */

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <vector>

#include <faiss/IndexFlat.h>
#include <faiss/IndexIVFFlat.h>

int main(int argc, char** argv) {
    const int d = 672;
    const int nb = 100000;
    const int nlist = 256;
    const int k = 1;
    const int nq_batch = 128;
    const int rounds = 8;
    int nprobe = 32;

    for (int i = 1; i < argc - 1; i++) {
        if (std::strcmp(argv[i], "--nprobe") == 0) {
            nprobe = std::atoi(argv[i + 1]);
        }
    }

    printf("Building index: nb=%d, d=%d, nlist=%d, nprobe=%d\n",
           nb, d, nlist, nprobe);

    std::mt19937 rng(42);
    std::uniform_real_distribution<float> distrib(-1.0f, 1.0f);

    std::vector<float> db((size_t)nb * d);
    for (auto& v : db) {
        v = distrib(rng);
    }
    for (int i = 0; i < nb; i++) {
        float norm = 0.0f;
        for (int j = 0; j < d; j++) {
            norm += db[(size_t)i * d + j] * db[(size_t)i * d + j];
        }
        norm = std::sqrt(norm);
        for (int j = 0; j < d; j++) {
            db[(size_t)i * d + j] /= norm;
        }
    }

    faiss::IndexFlatIP quantizer(d);
    faiss::IndexIVFFlat index(&quantizer, d, nlist, faiss::METRIC_INNER_PRODUCT);
    index.train(nb, db.data());
    index.add(nb, db.data());
    index.nprobe = nprobe;

    printf("Benchmarking: %d rounds x %d queries ...\n", rounds, nq_batch);

    std::vector<faiss::idx_t> labels((size_t)k * nq_batch);
    std::vector<float> distances_buf((size_t)k * nq_batch);
    std::vector<double> latencies;
    latencies.reserve(rounds);

    for (int r = 0; r < rounds; r++) {
        auto t0 = std::chrono::high_resolution_clock::now();
        index.search(nq_batch, db.data(), k, distances_buf.data(), labels.data());
        auto t1 = std::chrono::high_resolution_clock::now();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
        latencies.push_back(ms);
    }

    std::sort(latencies.begin(), latencies.end());

    double total_ms = 0.0;
    for (double v : latencies) {
        total_ms += v;
    }
    double qps = (rounds * nq_batch) / (total_ms / 1000.0);

    // percentile indices (0-based, rounds=8 gives coarse but useful buckets)
    auto pct = [&](int p) -> double {
        int idx = (rounds - 1) * p / 100;
        return latencies[idx];
    };

    printf("QPS: %.1f\n", qps);
    printf("Latency per batch of %d (ms): p50=%.2f  p95=%.2f  p99=%.2f\n",
           nq_batch, pct(50), pct(95), pct(99));

    return 0;
}
