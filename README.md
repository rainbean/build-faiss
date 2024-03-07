# build-faiss

Build faiss library

## Getting start

```Shell
$ ./scripts/build.sh && ./scripts/demo.sh && time ./build-demo/demo

    [0.000 s] Generating 100000 vectors in 128D for training
    [0.821 s] Training the index
    Training level-1 quantizer

    ...

    query  8:    1242   12357   73940   87457    7067
        dis: 7.72795 10.6769 11.0571 11.1061  11.184
    note that the nearest neighbor is not at distance 0 due to quantization errors

    ________________________________________________________
    Executed in    4.31 secs    fish           external
    usr time   17.31 secs  535.00 micros   17.31 secs
    sys time    0.80 secs  164.00 micros    0.80 secs
...
