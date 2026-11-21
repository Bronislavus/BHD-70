# Changes to MAME (the sound engine)

BHD-70 runs a modified build of MAME as its engine: the `d70` executable inside the
app bundle. Under the GPL-3.0 the source of *that* build has to travel with the program,
so it is here.

- `d70-poprawki-do-mame.patch` — all 32 changes as one patch
- base commit of `mamedev/mame`: `b9252e738e04140fe8ebf58a8b283a818dc5b497`

To build the engine:

```bash
git clone https://github.com/mamedev/mame.git mame-d70
cd mame-d70
git checkout b9252e738e04140fe8ebf58a8b283a818dc5b497
git apply ../mame/d70-poprawki-do-mame.patch
make SOURCES=src/mame/roland/roland_d70.cpp SUBTARGET=d70 -j10
```

The patch also carries chip emulation code taken from
<https://github.com/dsp56300/gearmulator> (GPL-3.0); see
`src/mame/roland/gearmulator/SOURCE-VERSION.txt` for the exact commit it came from.

MAME is the work of the MAME team and its contributors.
