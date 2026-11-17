# Whisper large-v3 loop experiment

| song | config | sec | rows | ref rows | WER | WER 2nd half | longest same-row run (at s) | block loop reps x rows (at s) | rows after last ref line + 5 s |
|---|---|---|---|---|---|---|---|---|---|
| Kinematic_-_Peyote | lyrics_v1 | 832.9 | 45 | 14 | 1.796 | 3.324 | 1 (None) | 4x2 (105) | 2 |
| Songwriterz_-_Back_In_Time | standard | 1353.0 | 45 | 46 | 0.479 | 0.705 | 1 (None) | 0x0 (None) | 0 |
| The_Rinn_-_Voices__2017_Version_ | standard | 279.2 | 43 | 46 | 1.000 | 1.000 | 1 (None) | 21x2 (0) | 0 |

## Kinematic_-_Peyote.lyrics_v1
```
   0.00   26.34 I'm asleep at the wheel and there's a car in the highway
  30.00   36.92 Yet we're tied through the night like a P.O.D. McQueen
  36.92   40.64 How much further is it?
  40.64   44.80 Ain't you so exquisite?
  44.80   52.20 I hope we can't stop in time
  52.20   57.76 Now you don't wanna dance, cause you're looking right through you
  57.76   59.64 Oh-oh-oh-oh-oh
  59.64   74.68 And the clothes that you wear, we don't need to stare
  74.68   82.12 Now the sky is on fire and the desert is freezing
  82.12   89.28 Wonder how I'm alive when I'm not even breathing
  89.28   90.32 How much further is it?
  90.32   91.36 Ain't you so exquisite?
  91.36   92.36 I hope we can't stop in time
  92.36   93.36 How much further is it?
  93.36   94.36 Ain't you so exquisite?
  94.36   95.36 I hope we can't stop in time
  95.36   96.36 Now you don't wanna dance, cause you're looking right through you
  96.36   97.36 Oh-oh-oh-oh-oh-oh
  97.36   98.36 And the clothes that you wear, we don't need to stare
  98.36   99.36 Oh-oh-oh-oh-oh-oh
  99.36  100.36 And the clouds that you wear, we don't need to stare
 100.36  101.36 Oh-oh-oh-oh-oh-oh
 101.36  102.36 And the clouds that you wear, we don't need to stare
 102.36  103.36 Oh-oh-oh-oh-oh-oh
 103.36  104.36 And the clouds that you wear, we don't need to stare
 104.36  105.36 Oh-oh-oh-oh-oh-oh-oh
 105.36  106.36 And the clouds that you wear, we don't need to stare
 106.36  107.36 Oh-oh-oh-oh-oh-oh
 107.36  108.36 And the clouds that you wear, we don't need to stare
 108.36  109.36 Oh-oh-oh-oh-oh-oh
 109.36  110.36 And the clouds that you wear, we don't need to stare
 110.36  111.36 Oh-oh-oh-oh-oh-oh
 111.36  112.36 And the clouds that you wear, we don't need to stare
 112.36  113.36 Oh-oh-oh-oh-oh-oh
 113.36  114.36 And the clouds that you wear, we don't need to stare
 114.36  115.36 Oh-oh-oh-oh-oh-oh-oh
 115.36  116.36 And the clouds that you wear, we don't need to stare
 116.36  117.36 Oh-oh-oh-oh-oh-oh-oh
 117.36  118.36 And the clouds that you wear, we don't need to stare
 118.36  119.36 Oh-oh-oh-oh-oh-oh-oh
 119.36  120.36 And the clouds that you wear, we don't need to stare
 120.36  121.36 Oh-oh-oh-oh-oh-oh-oh
 121.36  131.36 What they want to, oh-oh-oh-oh-oh-oh-oh-oh Cause the truth of it is, we don't really care
 151.36  181.34 Cause the truth of it is, we don't really care
 181.36  182.92 And that's quite enough of that.
```
## Songwriterz_-_Back_In_Time.standard
```
   0.00   12.24 Honey, I told you something
  12.24   15.02 Sorry, I didn't hear
  15.02   17.66 Maybe there was something
  17.66   20.58 Yeah, yeah, yeah, stuck in your ear
  20.58   26.00 Why is it every time you say you do, you don't?
  26.54   31.52 Maybe I just thought that you were talking on the phone
  31.52   36.34 Honey, you're looking lovely tonight
  36.34   39.14 Sorry, you're wasting time
  39.14   41.94 Baby, this ain't your lucky night
  41.94   44.22 Well, trying ain't a crime
  44.22   49.82 Why is it every time I like to do, you don't?
  50.52   55.10 Maybe you could try a little romance and a comb
  55.10   56.02 Let's go
  56.02   56.52 Baby
  56.54   58.26 Back in time
  58.26   61.58 Way back when we were
  61.58   65.08 La, la, la, la, la, la, la, la
  65.08   68.54 Now it's married life
  69.12   72.64 And a daily stride to be
  72.64   74.78 La, la, la, la, la, la
  74.78   78.36 La, la, la, la, la, la, la, la
  78.36   81.80 La, la, la, la, la, la, la, la, la
  81.80   88.54 Honey, you're getting older
  88.54   90.76 Yeah, you're still 29
  90.76   93.90 And maybe things are colder
  93.90   97.02 But honey, you're still your mind
  97.02  100.00 Guess it's easy to forget
 100.00  102.12 No more, no matter why
 102.12  105.82 Could it be the la, la magic
 105.82  107.78 Keeping love alive
 107.78  110.88 Let's go back in time
 110.88  114.26 Way back when we were
 114.26  117.84 La, la, la, la, la, la, la, la
 117.84  121.98 Back when you and I
 121.98  125.26 Still had time to be
 125.26  128.28 La, la, la, la, la, la, la, la
 128.28  134.04 La-la-la-la-la, la-la-la-la-la-la-la-la-la
 157.48  161.02 Let's go back in time
 161.02  164.14 Way back when we were
 164.14  168.78 La-la-la-la-la, la-la-la-la-la-la-la-la-la-la-la-la-la-la-la-la-la
 168.78  171.98 Back when you and I
 171.98  175.24 Still had time to be
 175.24  180.24 La-la-la-la-la, let's go back in time
 180.24  183.58 Way back when we were
 183.58  194.68 Now it's married life, still we have to try to be
```
## The_Rinn_-_Voices__2017_Version_.standard
```
   0.00   10.00 ♪♪♪
  10.00   20.00 ♪♪♪
  20.00   30.00 ♪♪♪
  30.00   40.00 ♪♪♪
  40.00   50.00 ♪♪♪
  50.00   54.00 ♪♪♪
  54.00   58.00 ♪♪♪
  58.00   62.00 ♪♪♪
  62.00   66.00 ♪♪♪
  66.00   70.00 ♪♪♪
  70.00   74.00 ♪♪♪
  74.00   76.00 ♪♪♪
  76.00   78.00 ♪♪♪
  78.00   80.00 ♪♪♪
  80.00   84.00 ♪♪♪
  84.00   88.00 ♪♪♪
  88.00   92.00 ♪♪♪
  92.00   96.00 ♪♪♪
  96.00  100.00 ♪♪♪
 100.00  104.00 ♪♪♪
 104.00  108.00 ♪♪♪
 108.00  110.00 ♪♪♪
 110.00  114.00 ♪♪♪
 114.00  120.00 ♪♪♪
 120.00  122.00 ♪♪♪
 122.00  124.00 ♪♪♪
 124.00  130.00 ♪♪♪
 130.00  132.00 ♪♪♪
 132.00  134.00 ♪♪♪
 134.00  136.00 ♪♪♪
 136.00  138.00 ♪♪♪
 138.00  140.00 ♪♪♪
 140.00  150.00 ♪♪♪
 150.00  160.00 ♪♪♪
 160.00  170.00 ♪♪♪
 170.00  180.00 ♪♪♪
 180.00  190.00 ♪♪♪
 190.00  200.00 ♪♪♪
 200.00  210.00 ♪♪♪
 210.00  220.00 ♪♪♪
 220.00  228.00 ♪♪♪
 228.00  230.00 ♪♪♪
 230.00  259.98 © transcript Emily Beynon
```
