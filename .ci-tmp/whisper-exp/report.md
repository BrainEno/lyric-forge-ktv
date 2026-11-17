# Whisper large-v3 loop experiment

| song | config | sec | rows | ref rows | WER | WER 2nd half | longest same-row run (at s) | block loop reps x rows (at s) | rows after last ref line + 5 s |
|---|---|---|---|---|---|---|---|---|---|
| Avercage_-_Embers | lyrics_v1 | 383.0 | 13 | 42 | 1.000 | 1.000 | 4 (0) | 0x0 (None) | 1 |
| Avercage_-_Embers | mc0 | 457.8 | 39 | 42 | 0.772 | 0.867 | 4 (152) | 0x0 (None) | 1 |
| Avercage_-_Embers | standard | 623.3 | 122 | 42 | 1.947 | 2.800 | 121 (2) | 60x2 (2) | 4 |
| Kinematic_-_Peyote | lyrics_v1 | 579.5 | 31 | 14 | 0.932 | 1.608 | 2 (135) | 0x0 (None) | 1 |
| Kinematic_-_Peyote | mc0 | 311.0 | 16 | 14 | 0.333 | 0.365 | 1 (None) | 0x0 (None) | 2 |
| Kinematic_-_Peyote | standard | 574.8 | 22 | 14 | 0.388 | 0.432 | 4 (134) | 0x0 (None) | 5 |
| Ridgway_-_Fire_Inside | lyrics_v1 | 515.6 | 99 | 50 | 1.188 | 3.337 | 2 (50) | 29x2 (217) | 3 |
| Ridgway_-_Fire_Inside | mc0 | 673.4 | 44 | 50 | 0.257 | 0.396 | 3 (258) | 0x0 (None) | 0 |
| Ridgway_-_Fire_Inside | standard | 733.8 | 48 | 50 | 0.230 | 0.455 | 4 (182) | 0x0 (None) | 0 |
| Songwriterz_-_Back_In_Time | lyrics_v1 | 1097.8 | 29 | 46 | 0.487 | 0.591 | 1 (None) | 0x0 (None) | 0 |
| Songwriterz_-_Back_In_Time | mc0 | 439.9 | 33 | 46 | 0.340 | 0.500 | 1 (None) | 0x0 (None) | 0 |
| Songwriterz_-_Back_In_Time | standard | 858.8 | 46 | 46 | 0.458 | 0.648 | 2 (195) | 0x0 (None) | 0 |
| The.madpix.project_-_One_Way_Street | lyrics_v1 | 458.7 | 15 | 30 | 0.951 | 0.963 | 10 (0) | 5x2 (0) | 0 |
| The.madpix.project_-_One_Way_Street | mc0 | 277.9 | 24 | 30 | 0.082 | 0.074 | 2 (122) | 0x0 (None) | 0 |
| The.madpix.project_-_One_Way_Street | standard | 373.1 | 27 | 30 | 0.104 | 0.123 | 2 (122) | 0x0 (None) | 0 |
| The_Rinn_-_Voices__2017_Version_ | lyrics_v1 | 314.0 | 43 | 46 | 0.330 | 0.446 | 1 (None) | 0x0 (None) | 0 |
| The_Rinn_-_Voices__2017_Version_ | mc0 | 370.4 | 39 | 46 | 0.340 | 0.365 | 1 (None) | 0x0 (None) | 0 |
| The_Rinn_-_Voices__2017_Version_ | standard | 438.1 | 56 | 46 | 0.995 | 0.986 | 1 (None) | 27x2 (0) | 0 |

## Avercage_-_Embers.lyrics_v1
```
   0.00   29.98 作詞・作曲・編曲 初音ミク
  30.00   59.98 作詞・作曲・編曲 初音ミク
  60.00   89.98 作詞・作曲・編曲 初音ミク
  90.00  119.98 作詞・作曲・編曲 初音ミク
 120.00  149.86 作曲・作曲・編曲 初音ミク
 149.86  149.96 作曲・作曲・編曲 初音ミク
 149.96  149.98 作曲・作曲・編曲 初音ミク
 150.00  179.78 作詞・作曲・編曲 初音ミク
 179.80  179.88 作曲・作曲・編曲 初音ミク
 179.88  179.98 作曲・作曲・編曲 初音ミク
 180.00  209.98 作曲・作曲・編曲 初音ミク
 210.00  239.98 作曲・作曲・編曲 初音ミク
 240.00  241.88 ご視聴ありがとうございました
```
## Avercage_-_Embers.mc0
```
   0.00   29.98 作詞・作曲・編曲 初音ミク
  30.00   59.98 作詞・作曲・編曲 初音ミク
  60.00   64.22 Your mind
  64.22   67.18 You'll fall with the danger
  67.18   70.58 So long, take my hand
  70.58   77.26 It's okay, I'll always be with you
  77.26   80.02 One day it all
  80.02   81.58 Will come forever
  81.58   83.48 Will come forever
  83.48   87.42 Don't close your eyes
  87.42   88.98 Will come forever
  88.98   91.26 You'll come forever
  91.26   96.64 Just feel the water
  96.64  101.14 It's all your past and gone
 101.14  105.30 Hey, you're on your own
 105.30  110.58 You'll be far behind the time
 110.58  117.38 My heart is feeling the heart of a lonely man
 117.38  121.64 No name for you
 121.64  125.32 No hope for me
 125.32  130.26 One day it all will come forever
 130.26  132.76 Will come forever
 132.76  135.76 Don't close your eyes
 135.76  137.66 Will come forever
 137.66  140.46 Will come forever
 147.38  152.38 🐯 Sound Hodori 사운드 호돌이 サウンドゥ ホドリ
 152.38  157.38 Instagram & Twitter ホドリ
 157.38  162.38 Instagram & Twitter ホドリ
 162.38  167.38 Instagram & Twitter ホドリ
 167.38  172.38 Instagram & Twitter ホドリ
 172.38  179.12 So I promise
 179.12  193.12 Oh, I'll tell you all
 193.12  197.48 Oh, go forever, go forever
 197.48  203.06 Don't close your eyes
 203.06  207.52 Oh, go forever, go forever
 207.52  213.28 Let's go, my friend
 213.28  215.96 Let's go, my friend
 215.96  223.42 Never stop, let's once in the end
 223.42  230.20 The friends remember, but leaving members will die
 237.52  242.52 サブタイトル キヨヒヨ
```
## Avercage_-_Embers.standard
```
   0.00    2.00 作詞・作曲・編曲 大島 美穂
   2.00    4.00 歌:大島 美穂
   4.00    6.00 歌:大島 美穂
   6.00    8.00 歌:大島 美穂
   8.00   10.00 歌:大島 美穂
  10.00   12.00 歌:大島 美穂
  12.00   14.00 歌:大島 美穂
  14.00   16.00 歌:大島 美穂
  16.00   18.00 歌:大島 美穂
  18.00   20.00 歌:大島 美穂
  20.00   22.00 歌:大島 美穂
  22.00   24.00 歌:大島 美穂
  24.00   26.00 歌:大島 美穂
  26.00   28.00 歌:大島 美穂
  28.00   30.00 歌:大島 美穂
  30.00   32.00 歌:大島 美穂
  32.00   34.00 歌:大島 美穂
  34.00   36.00 歌:大島 美穂
  36.00   38.00 歌:大島 美穂
  38.00   40.00 歌:大島 美穂
  40.00   42.00 歌:大島 美穂
  42.00   44.00 歌:大島 美穂
  44.00   46.00 歌:大島 美穂
  46.00   48.00 歌:大島 美穂
  48.00   50.00 歌:大島 美穂
  50.00   52.00 歌:大島 美穂
  52.00   54.00 歌:大島 美穂
  54.00   56.00 歌:大島 美穂
  56.00   58.00 歌:大島 美穂
  58.00   60.00 歌:大島 美穂
  60.00   62.00 歌:大島 美穂
  62.00   64.00 歌:大島 美穂
  64.00   66.00 歌:大島 美穂
  66.00   68.00 歌:大島 美穂
  68.00   70.00 歌:大島 美穂
  70.00   72.00 歌:大島 美穂
  72.00   74.00 歌:大島 美穂
  74.00   76.00 歌:大島 美穂
  76.00   78.00 歌:大島 美穂
  78.00   80.00 歌:大島 美穂
  80.00   82.00 歌:大島 美穂
  82.00   84.00 歌:大島 美穂
  84.00   86.00 歌:大島 美穂
  86.00   88.00 歌:大島 美穂
  88.00   90.00 歌:大島 美穂
  90.00   92.00 歌:大島 美穂
  92.00   94.00 歌:大島 美穂
  94.00   96.00 歌:大島 美穂
  96.00   98.00 歌:大島 美穂
  98.00  100.00 歌:大島 美穂
 100.00  102.00 歌:大島 美穂
 102.00  104.00 歌:大島 美穂
 104.00  106.00 歌:大島 美穂
 106.00  108.00 歌:大島 美穂
 108.00  110.00 歌:大島 美穂
 110.00  112.00 歌:大島 美穂
 112.00  114.00 歌:大島 美穂
 114.00  116.00 歌:大島 美穂
 116.00  118.00 歌:大島 美穂
 118.00  120.00 歌:大島 美穂
 120.00  122.00 歌:大島 美穂
 122.00  124.00 歌:大島 美穂
 124.00  126.00 歌:大島 美穂
 126.00  128.00 歌:大島 美穂
 128.00  130.00 歌:大島 美穂
 130.00  132.00 歌:大島 美穂
 132.00  134.00 歌:大島 美穂
 134.00  136.00 歌:大島 美穂
 136.00  138.00 歌:大島 美穂
 138.00  140.00 歌:大島 美穂
 140.00  142.00 歌:大島 美穂
 142.00  144.00 歌:大島 美穂
 144.00  146.00 歌:大島 美穂
 146.00  148.00 歌:大島 美穂
 148.00  150.00 歌:大島 美穂
 150.00  152.00 歌:大島 美穂
 152.00  154.00 歌:大島 美穂
 154.00  156.00 歌:大島 美穂
 156.00  158.00 歌:大島 美穂
 158.00  160.00 歌:大島 美穂
 160.00  162.00 歌:大島 美穂
 162.00  164.00 歌:大島 美穂
 164.00  166.00 歌:大島 美穂
 166.00  168.00 歌:大島 美穂
 168.00  170.00 歌:大島 美穂
 170.00  172.00 歌:大島 美穂
 172.00  174.00 歌:大島 美穂
 174.00  176.00 歌:大島 美穂
 176.00  178.00 歌:大島 美穂
 178.00  180.00 歌:大島 美穂
 180.00  182.00 歌:大島 美穂
 182.00  184.00 歌:大島 美穂
 184.00  186.00 歌:大島 美穂
 186.00  188.00 歌:大島 美穂
 188.00  190.00 歌:大島 美穂
 190.00  192.00 歌:大島 美穂
 192.00  194.00 歌:大島 美穂
 194.00  196.00 歌:大島 美穂
 196.00  198.00 歌:大島 美穂
 198.00  200.00 歌:大島 美穂
 200.00  202.00 歌:大島 美穂
 202.00  204.00 歌:大島 美穂
 204.00  206.00 歌:大島 美穂
 206.00  208.00 歌:大島 美穂
 208.00  210.00 歌:大島 美穂
 210.00  212.00 歌:大島 美穂
 212.00  214.00 歌:大島 美穂
 214.00  216.00 歌:大島 美穂
 216.00  218.00 歌:大島 美穂
 218.00  220.00 歌:大島 美穂
 220.00  222.00 歌:大島 美穂
 222.00  224.00 歌:大島 美穂
 224.00  226.00 歌:大島 美穂
 226.00  228.00 歌:大島 美穂
 228.00  230.00 歌:大島 美穂
 230.00  232.00 歌:大島 美穂
 232.00  234.00 歌:大島 美穂
 234.00  236.00 歌:大島 美穂
 236.00  238.00 歌:大島 美穂
 238.00  240.00 歌:大島 美穂
 240.00  242.00 歌:大島 美穂
 242.00  244.00 歌:大島 美穂
```
## Kinematic_-_Peyote.lyrics_v1
```
   0.00   26.34 I'm asleep at the wheel and there's a car in the highway
  30.00   36.92 Yet we're tied through the night like a P.O.D. McQueen
  36.92   40.64 How much further is it?
  40.64   44.80 Ain't you so exquisite?
  44.80   52.24 I hope we can't stop in time
  52.24   57.76 Now you don't wanna dance, cause you're looking right through you
  57.76   59.64 Oh-oh-oh-oh-oh
  59.64   74.76 And the clothes that you wear, we don't need to stare
  74.76   82.04 Now the sky is on fire and the desert is freezing
  82.04   89.28 Wonder how I'm alive when I'm not even breathing
  89.28   90.28 How much further is it?
  90.28   91.28 Ain't you so exquisite?
  91.28   92.28 I hope we can't stop in time
  92.28   93.28 Now you don't wanna dance, cause you're looking right through you
  93.28   94.28 Oh-oh-oh-oh-oh-oh And the clothes that you wear, we don't need to
  94.28   95.28 stare
  95.28   96.28 Oh-oh-oh-oh-oh-oh And the sky is on fire and the desert is freezing
  96.28   97.28 Wonder how I'm alive when I'm not even breathing
  97.28   98.28 Now the sky is on fire and the desert is freezing
  98.28   99.28 Wonder how I'm alive when I'm not even breathing
  99.28  100.28 How much further is it?
 100.28  101.28 Ain't you so exquisite?
 101.28  102.28 I hope we can't stop in time
 102.28  103.28 Now you don't wanna dance, cause you're looking right through you
 103.28  104.28 Oh-oh-oh-oh-oh-oh And the clothes that you wear, we don't need to
 104.28  105.28 stare
 105.28  106.28 Oh-oh-oh-oh-oh-oh And the people you know, they say what they want
 106.28  107.28 to
 107.28  107.28 Oh-oh-oh-oh-oh-oh And the truth of it is, we don't really care
 135.28  165.26 We'll be right back.
 165.28  182.94 We'll be right back.
```
## Kinematic_-_Peyote.mc0
```
   0.00   24.42 I'm Asleep at the Wheel
  30.00   35.00 Yet we tear through the night like a P.O.D. microwave
  37.00   40.00 How much further is it?
  41.00   44.00 Ain't you so exquisite?
  45.00   49.00 I hope we can't stop inside
  52.00   57.00 Now you don't wanna dance, cause you're looking right through you
  58.00   64.26 Oh, and the clothes that you wear, we don't need to stare
  64.26   78.10 Now the sky is on fire and the desert is freezing
  78.10   85.40 Wonder how I'm alive when I'm not even breathing
  88.00  100.70 How much further is it? Ain't it so exquisite? I hope we can stop in time
 103.40  107.70 Now you don't wanna dance, cause we'll look around for you
 108.54  116.00 And the clothes that you wear, we don't need to stare
 116.00  122.94 Oh, but the people you know, they say what they want to
 122.94  130.94 Oh, cause the truth of it is, we don't really care
 146.00  175.98 We'll see you next time.
 176.00  182.94 And that's quite enough of that
```
## Kinematic_-_Peyote.standard
```
   0.00   24.42 I'm Asleep at the Wheel
  30.00   34.50 Yet we're tied through the night like a P.O.D. microwave.
  37.00   40.50 How much further is it?
  40.50   44.50 Ain't you so exquisite?
  44.50   49.00 I hope we can't stop inside.
  52.00   57.00 Now you don't wanna dance, cause you're looking right through you.
  59.50   64.50 And the clothes that you wear, we don't need to stare.
  74.50   78.50 Now the sky is on fire and the desert is freezing.
  81.50   86.50 Wonder how I'm alive when I'm not even breathing.
  89.00   92.00 How much further is it?
  92.00   96.00 Ain't you so exquisite?
  96.00  101.00 I hope we can't stop inside.
 104.00  109.00 Now you don't wanna dance, cause you're looking right through you.
 111.00  116.00 And the clothes that you wear, we don't need to stare.
 118.50  123.50 But the people you know, they say what they want to.
 126.00  131.00 Cause the truth of it is, we don't really care.
 133.50  140.50 Music
 140.50  145.50 Music
 145.50  147.50 Music
 147.50  148.00 Music
 148.00  177.98 Thanks for watching!
 178.00  183.04 Don't forget to like, comment, and subscribe!
```
## Ridgway_-_Fire_Inside.lyrics_v1
```
  30.00   44.70 I got a lot on my mind and all of the time be trying to do right
  44.70   49.72 I may have lost a life but I'm keeping it tight, never give up the fight, no
  49.72   52.82 When my life was so rigged
  52.82   55.18 When my life was so rigged
  55.18   57.50 Got to keep it all in check
  57.50   59.34 I keep it all in check
  59.34   74.46 Even in the darkest days, got a trail to blaze, gonna stick to my ways
  74.46   79.56 I used to be caught in a phase where life was a maze until I saw the sun's rays
  79.56   82.32 When your life is so rigged
  82.32   84.72 When your life is so rigged
  84.72   88.68 You got to take the first step
  88.68   91.86 Whoa-oh-oh-oh-oh
  91.86   94.44 Paddle on through the waves now
  94.44   96.76 Whoa-oh-oh-oh-oh
  96.76   99.32 Gonna take me to that place
  99.32  101.88 Whoa-oh-oh-oh-oh
 101.88  104.24 Find that fire inside
 104.24  106.70 Whoa-oh-oh-oh-oh
 106.70  109.44 It's a fate that you decide
 118.68  132.76 When I feel like I'm losing control
 132.76  137.74 Gotta reach within my soul
 137.74  142.54 And if you're ever feeling low, yeah
 142.54  148.44 You gotta take the first step and go, yeah
 148.44  151.36 Take that first step to the right
 151.36  153.82 Got to find what's inside
 153.82  156.60 Before we run out of time, run out of time
 156.60  159.08 Run out of time
 159.08  161.12 Whoa-oh-oh-oh-oh
 161.12  163.70 Headlong through the waves now
 163.70  166.18 Whoa-oh-oh-oh-oh
 166.18  168.60 Gonna take me to that place
 168.60  171.16 Whoa-oh-oh-oh-oh
 171.16  173.52 Find that fire inside
 173.52  176.10 Whoa-oh-oh-oh-oh
 176.10  178.20 It's a fate that you decide
 178.20  180.92 That you decide
 180.92  185.96 That you decide
 207.96  210.68 That you decide to take the first step
 210.68  212.88 And if you're ever feeling low, yeah
 212.88  214.68 Gotta reach within my soul
 214.68  216.68 Gotta reach within my soul
 216.68  218.68 Gonna take me to that place
 218.68  220.68 Where I'm gonna be, yeah
 220.68  222.68 Gonna take me to that place
 222.68  224.68 Where I'm gonna be, yeah
 224.68  226.68 Gonna take me to that place
 226.68  228.68 Where I'm gonna be, yeah
 228.68  230.68 Gonna take me to that place
 230.68  232.68 Where I'm gonna be, yeah
 232.68  234.68 Gonna take me to that place
 234.68  236.68 Where I'm gonna be, yeah
 236.68  237.72 Gonna take me to that place
 237.72  238.72 Where I'm gonna be, yeah
 238.72  239.72 Gonna take me to that place
 239.72  240.72 Where I'm gonna be, yeah
 240.72  241.72 Gonna take me to that place
 241.72  242.72 Where I'm gonna be, yeah
 242.72  243.72 Gonna take me to that place
 243.72  244.72 Where I'm gonna be, yeah
 244.72  245.72 Gonna take me to that place
 245.72  246.72 Where I'm gonna be, yeah
 246.72  247.72 Gonna take me to that place
 247.72  248.72 Where I'm gonna be, yeah
 248.72  249.72 Gonna take me to that place
 249.72  250.72 Where I'm gonna be, yeah
 250.72  251.72 Gonna take me to that place
 251.72  252.72 Where I'm gonna be, yeah
 252.72  253.72 Gonna take me to that place
 253.72  254.72 Where I'm gonna be, yeah
 254.72  255.72 Gonna take me to that place
 255.72  256.72 Where I'm gonna be, yeah
 256.72  257.72 Gonna take me to that place
 257.72  258.72 Where I'm gonna be, yeah
 258.72  259.72 Gonna take me to that place
 259.72  260.72 Where I'm gonna be, yeah
 260.72  261.72 Gonna take me to that place
 261.72  262.72 Where I'm gonna be, yeah
 262.72  263.72 Gonna take me to that place
 263.72  264.72 Where I'm gonna be, yeah
 264.72  265.72 Gonna take me to that place
 265.72  266.72 Where I'm gonna be, yeah
 266.72  267.72 Gonna take me to that place
 267.72  268.72 Where I'm gonna be, yeah
 268.72  269.72 Gonna take me to that place
 269.72  270.72 Where I'm gonna be, yeah
 270.72  271.72 Gonna take me to that place
 271.72  272.72 Where I'm gonna be, yeah
 272.72  273.72 Gonna take me to that place
 273.72  274.72 Where I'm gonna be, yeah
 274.72  275.72 Gonna take me to that place
 275.72  276.72 Where I'm gonna be, yeah
 276.72  277.72 Gonna take me to that place
 277.72  278.72 Where I'm gonna be, yeah
 278.72  279.72 Gonna take me to that place
 279.72  280.72 Where I'm gonna be, yeah
 280.72  281.72 Gonna take me to that place
 281.72  282.72 Where I'm gonna be, yeah
 282.72  283.72 Gonna take me to that place
 283.72  284.72 Where I'm gonna be, yeah
```
## Ridgway_-_Fire_Inside.mc0
```
   0.00   20.00 🎵
  30.00   44.70 I got a lot on my mind and all of the time I've been trying to do right
  44.70   49.74 I may have lost a life but I'm keeping it tight, never give up the fight, no
  49.74   52.80 When my life was so rigged
  52.80   55.18 When my life was so rigged
  55.18   57.50 Got to keep it all in check
  57.50   59.34 I keep it all in check
  59.34   71.54 Even in the darkest days
  71.54   72.82 Got a trail to blaze
  72.82   74.46 Gonna stick to my ways
  74.46   76.52 I used to be caught in a phase
  76.52   77.78 Where life was a maze
  77.78   79.58 Until I saw the sun's rays
  79.58   82.28 When your life is a wreck
  82.28   84.38 When your life is a wreck
  84.38   88.44 You got to take the first step
  88.44   99.32 Whoa, paddling through the waves now Whoa, gonna take me to that place
  99.32  109.42 Whoa, find that fire inside Whoa, it's a fate that you decide
 118.44  132.76 When I feel like I'm losing control
 132.76  137.76 Gotta reach within my soul
 137.76  142.54 And if you're ever feeling low, yeah
 142.54  146.72 You gotta take the first step
 146.72  148.46 And go, yeah
 148.46  151.36 Take that first step to the right
 151.36  153.82 Got to find what's inside
 153.82  156.60 Before we run out of time, run out of time
 156.60  159.08 Run out of time
 159.08  161.22 Whoa-oh-oh-oh-oh
 161.22  163.68 Headlong through the waves now
 163.68  166.10 Whoa-oh-oh-oh-oh
 166.10  168.60 Gonna take me to that place
 168.60  171.16 Whoa-oh-oh-oh-oh
 171.16  173.50 Find that fire inside
 173.50  176.10 Whoa-oh-oh-oh-oh
 176.10  179.00 It's a fate that you decide
 179.00  184.68 That you decide
 206.10  236.08 guitar solo
 236.10  243.30 I'm palin' on, I'm palin' strong
 243.30  248.22 Find the fire, find the fire
 248.22  253.24 I'm palin' on, I'm palin' strong
 253.24  258.20 Find the fire, find the fire
 258.20  262.56 Fire in the fire
 262.56  267.92 Fire in the fire
 267.92  272.44 Fire in the fire
```
## Ridgway_-_Fire_Inside.standard
```
  30.00   44.70 I got a lot on my mind and all of the time I've been trying to do right
  44.70   49.74 I may have lost a life but I'm keeping it tight, never give up the fight, no
  49.74   52.80 When my life was so rigged
  52.80   55.18 When my life was so rigged
  55.18   57.50 Got to keep it all in check
  57.50   59.34 I keep it all in check
  59.34   74.46 Even in the darkest days, got a trail to blaze, gonna stick to my ways
  74.46   79.58 I used to be caught in a phase where life was a maze until I saw the sun's rays
  79.58   82.32 When your life is so rigged
  82.32   84.92 When your life is so rigged
  84.92   88.68 You got to take the first step
  88.68   91.82 Whoa-oh-oh-oh-oh
  91.82   94.42 Paddle on through the waves now
  94.42   96.78 Whoa-oh-oh-oh-oh
  96.78   99.32 Gonna take me to that place
  99.32  101.88 Whoa-oh-oh-oh-oh
 101.88  104.24 Find that fire inside
 104.24  106.70 Whoa-oh-oh-oh-oh
 106.70  109.42 It's a fate that you decide
 118.68  132.76 When I feel like I'm losing control
 132.76  137.74 Gotta reach within my soul
 137.74  142.54 And if you're ever feeling low, yeah
 142.54  148.44 You gotta take the first step and go, yeah
 148.44  151.36 Take that first step to the right
 151.36  153.82 Got to find what's inside
 153.82  156.60 Before we run out of time, run out of time
 156.60  159.08 Run out of time
 159.08  161.12 Whoa-oh-oh-oh-oh
 161.12  163.70 Headlong through the waves now
 163.70  166.20 Whoa-oh-oh-oh-oh
 166.20  168.60 Gonna take me to that place
 168.60  171.16 Whoa-oh-oh-oh-oh
 171.16  173.50 Find that fire inside
 173.50  176.10 Whoa-oh-oh-oh-oh
 176.10  178.20 It's a fate that you decide
 178.20  182.04 It's a fate that you decide
 182.04  186.96 That you decide
 186.96  190.96 That you decide
 190.96  198.96 That you decide
 198.96  207.96 That you decide
 207.96  237.94 guitar solo
 237.96  243.30 Whoa, I'm peddling on, I'm peddling strong
 243.30  247.72 Whoa, find the fire, find the fire
 247.72  253.24 Whoa, I'm peddling on, I'm peddling strong
 253.24  258.04 Whoa, find the fire, find the fire
 258.04  262.54 Find the fire
 262.54  267.28 Find the fire
 267.96  272.22 Find the fire
```
## Songwriterz_-_Back_In_Time.lyrics_v1
```
   0.00   12.24 Honey, I told you something
  12.24   15.02 Sorry, I didn't hear
  15.02   17.66 Maybe there was something
  17.66   20.46 Yeah, yeah, yeah, stuck in your ear
  20.46   26.00 Why is it every time you say you do, you don't?
  26.54   31.52 Maybe I just thought that you were talking on the phone
  31.52   36.34 Honey, you're looking lovely tonight
  36.34   39.14 Sorry, you're wasting time
  39.14   41.94 Baby, this ain't your lucky night
  41.94   44.26 Well, trying ain't a crime
  44.26   49.80 Why is it every time I like to do, you don't?
  50.52   55.10 Maybe you could try a little romance and a comb
  55.10   56.02 Let's go
  56.02   56.52 Baby
  56.52   58.24 Back in time
  58.24   61.58 Way back when we were
  61.58   65.06 La, la, la, la, la, la, la, la
  65.06   69.12 Now it's married life
  69.12   72.62 And a daily stride to be
  72.62   82.12 La, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la, la.
  86.40   96.92 Honey, you're getting older. Yeah, you're still 29. And maybe things are colder. But honey, you're still your mind.
  97.26  107.76 Guess it's easy to forget. No more than men are white. Could it be the la, la magic keeping love alive?
 108.02  118.26 Let's go back in time. Way back when we were la, la, la, la, la, la, la, la, la, la.
 118.72  127.24 Back when you and I still had time to be. La, la, la, la, la, la.
 127.26  134.12 La la la la la la la la la la la la la la la la la
 157.26  164.16 Let's go back in time, way back when we were
 164.16  175.24 La la la la la la la la la, back when you and I still had time to be
 175.24  183.58 La la la la la, let's go back in time, way back when we were
 183.58  194.66 Now it's married life, still we have to try to be
```
## Songwriterz_-_Back_In_Time.mc0
```
   0.00   12.24 Honey, I told you something
  12.24   15.02 Sorry, I didn't hear
  15.02   17.66 Maybe there was something
  17.66   20.58 Yeah, yeah, yeah, stuck in your ear
  20.58   26.00 Why is it every time you say you do, you don't?
  26.68   31.52 Maybe I just thought that you were talking on the phone
  31.52   36.36 Honey, you're looking lovely tonight
  36.36   39.14 Sorry, you're wasting time
  39.14   41.94 Baby, this ain't your lucky night
  41.94   44.22 Well, trying ain't a crime
  44.22   49.80 Why is it every time I like to do, you don't?
  50.60   55.10 Maybe you could try a little romance and a comb
  55.10   64.76 Let's go back in time, way back when we were la-la-la-la-la-la-la-la.
  65.76   79.76 Now it's married life and a daily stride to be la-la-la-la-la-la-la-la-la.
  85.10   90.76 Honey, you're getting older Yeah, you're still 29
  90.76   97.02 And maybe things are colder But honey, you're still your mind
  97.02  102.12 Guess it's easy to forget The more the better, why?
 102.98  107.78 Could it be the la-la magic Keeping love alive?
 107.78  114.24 Let's go back in time Way back when we were
 114.24  125.30 Back when you and I still had time to be
 144.24  161.04 Let's go back in time
 161.04  164.14 Way back when we were
 164.14  168.04 La, la, la, la, la, la, la, la
 168.04  171.96 Back when you and I
 171.96  175.24 Still had time to be
 175.24  177.12 La la la la la
 177.12  180.24 Let's go back in time
 180.24  183.58 Way back when we were
 183.58  186.48 La la la la la la la
 186.48  191.04 Now it's married life
 191.04  194.64 Still we had to try to be
 194.64  196.90 La la la la la
 196.90  202.44 La la la la la, la la la la la la la la
```
## Songwriterz_-_Back_In_Time.standard
```
   0.00   12.24 Honey, I told you something
  12.24   15.02 Sorry, I didn't hear
  15.02   17.66 Maybe there was something
  17.66   20.60 Yeah, yeah, yeah, stuck in your ear
  20.60   26.00 Why is it every time you say you do, you don't?
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
  61.58   65.06 La, la, la, la, la, la, la, la
  65.06   68.54 Now it's married life
  69.12   72.64 And a daily stride to be
  72.64   74.82 La, la, la, la, la, la
  74.82   78.38 La, la, la, la, la, la, la, la
  78.38   81.80 La, la, la, la, la, la, la, la, la
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
 114.26  117.86 La, la, la, la, la, la, la, la
 117.86  121.98 Back when you and I
 121.98  125.28 Still had time to be
 125.28  128.24 La, la, la, la, la, la, la, la
 128.24  134.00 La la la la la la la la la la la la la la la la la.
 157.40  164.16 Let's go back in time, way back when we were.
 164.38  167.94 La la la la la la la la la la.
 168.82  175.22 Back when you and I still had time to be.
 175.48  177.14 La la la la la.
 177.36  183.56 Let's go back in time, way back when we were.
 183.56  186.56 La la la la la la la la la.
 186.56  194.66 Now it's married life, still we have to try to be
 194.66  196.44 La la la la la
 196.44  199.36 La la la la la
```
## The.madpix.project_-_One_Way_Street.lyrics_v1
```
   0.00   29.98 The.Madpix.Project is a production of The.Madpix.Project.
  30.00   59.98 The.Madpix.Project is a production of The.Madpix.Project
  60.00   89.52 The.Madpix.Project is a production of The.Madpix.Project
  89.52   89.98 The.Madpix.Project is a production of The.Madpix.Project
  89.98   89.98 The.Madpix.Project is a production of The.Madpix.Project
  89.98   89.98 The.Madpix.Project is a production of The.Madpix.Project
  89.98   89.98 The.Madpix.Project is a production of The.Madpix.Project
  89.98   89.98 The.Madpix.Project is a production of The.Madpix.Project
  89.98   89.98 The.Madpix.Project is a production of The.Madpix.Project
  89.98   89.98 The.Madpix.Project is a production of The.Madpix.Project
  89.98   89.98 The.Madpix.Project is a production of The.Madpix
  89.98   89.98 The.Madpix.Project is a production of The.Madpix.Project
  89.98  119.96 The.Madpix.Project is a production of The.Madpix.Project
 119.96  149.94 The.Madpix.Project is a production of The.Madpix.Project
 149.94  170.10 The.Madpix.Project is a production of The.Madpix.Project
```
## The.madpix.project_-_One_Way_Street.mc0
```
   0.00   17.56 Tears are like diamonds in my eyes
  17.56   20.96 Blind me so, now you're out of sight
  20.96   26.28 It's enough, it's too late to break this silence
  26.28   34.74 In a rose-colored view of us I got lost, could I realize
  34.74   40.24 All your lies would be blades and knives to stab me inside
  40.24   47.28 Who will save you from this dark? Who will fix your selfish heart?
  47.28   53.96 A one-way street, that's how you live Why do you always take and never give?
  56.28   83.28 🎵
  83.28   86.12 Wide awake, yeah I've crossed the line
  86.12   89.54 I'm coming home, I'm running back to real life
  89.54   94.60 To the start, where I could breathe in freely, baby
  94.60   99.12 Can't you see we run off time, chasing happiness
  99.12  101.80 While you get what you need
 101.80  106.20 There's nothing left of us, but bleeding blades and knives
 106.20  108.92 Tonight, you'll know how it feels
 108.92  112.28 A one-way street, that's how you live
 112.28  115.72 Why do you always take and never give?
 115.72  119.10 I'll walk away to help you see
 119.10  122.26 Our love is rolling down so easily
 122.26  124.54 A one-way street
 145.72  156.96 A one-way street
 156.96  160.44 You never give
 160.44  163.86 I'll walk away
 163.86  166.82 So easily
```
## The.madpix.project_-_One_Way_Street.standard
```
   0.00   14.34 ♪
  14.34   17.74 ♪ Tears are like diamonds in my eyes ♪
  17.74   21.20 ♪ Blind me so, now you're out of sight ♪
  21.20   28.14 ♪ It's enough, it's too late to break this silence ♪
  28.14   32.88 ♪ In a rose-colored view of us, I got lost ♪
  32.88   40.60 ♪ Could I realize, all your lies would be blades and knives to stab me inside? ♪
  40.60   47.36 ♪ Who will save you from this dark? Who will fix your selfish heart? ♪
  47.36   50.76 ♪ A one-way street, that's how you live ♪
  50.76   54.14 ♪ Why do you always take and never give? ♪
  58.14   83.14 ♪ ♪
  83.14   86.28 ♪ Wide awake, yeah, I've crossed the line ♪
  86.28   87.98 ♪ I'm coming home, I'm running back ♪
  87.98   91.04 ♪ To real life, to the start ♪
  91.04   95.72 ♪ Where I could breathe in freely, baby ♪
  95.72   97.90 ♪ Can't you see we run out of time? ♪
  97.90  102.78 ♪ Chasing happiness while you get what you need ♪
 102.78  106.24 ♪ There's nothing left of us but bleeding blades and knives ♪
 106.24  109.06 ♪ Tonight, you'll know how it feels ♪
 109.06  112.48 ♪ A one-way street, that's how you live ♪
 112.48  115.92 ♪ Why do you always take and never give? ♪
 115.92  117.82 ♪ I'll walk away ♪
 117.82  122.24 Help you see, our love is rolling down so easily
 122.24  124.54 A one-way street
 147.82  156.74 A one-way street
 156.74  160.44 You never give
 160.44  163.90 I walk away
 163.90  166.84 So easily
```
## The_Rinn_-_Voices__2017_Version_.lyrics_v1
```
  30.00   56.46 The Sun Is Fading
  56.46   58.26 Under Blood Red Sky
  58.26   59.54 The Rain Of Day
  59.54   62.34 Is Over
  62.34   66.04 Night Soon Will Break Free
  66.04   69.74 They Wake In The Eerie Glow Of Moonlight
  69.74   74.14 Forgot Ourselves Beyond Our Sight
  74.14   77.74 World Is Gone Forever Long Ago
  77.74   79.24 Lost In The Rise
  79.24   80.74 The Shine
  80.74   83.14 We Missed We Lost
  83.14   85.94 Remain In Shadows Of Last Dying
  85.94   89.08 Whispering In Their Moonlight
  89.08   94.38 Surprised You're Waking In The Morning
  94.38   98.88 Can't Understand Your Feelings
  98.88  102.68 And Where Do You Get These Thoughts?
 102.68  106.38 Inside Your Mind A Voice Is Calling
 106.38  110.68 For The Night To Rise At Your Side
 110.68  114.68 World Is Gone Forever Long Ago
 114.68  116.68 Lost In The Rise
 116.68  117.68 The Shine
 117.68  118.62 We Missed We Lost
 118.62  122.42 Remain In Shadows Of Last Dying
 122.42  127.42 Whispering In Their Moonlight
 127.42  129.42 So Hear Their Voice
 129.42  131.42 Sharing Their Yearning
 131.42  135.42 Give Their Deep Into You
 135.42  137.42 Hear Their Voice
 137.42  139.42 Sharing Their Memories
 139.42  145.42 Sacred Secrets From Fast Time
 148.62  178.60 guitar solo
 178.60  181.28 Forever, long ago, lost to the light
 181.28  186.20 The shine we've missed, we've lost, we've made
 186.20  191.30 In shadows of lost time, whispering in the moonlight
 191.30  196.78 So hear their voice, sharing their yearning
 196.78  200.48 Deep, deep, deep into you
 200.48  204.72 Hear their voice, sharing their memories
 204.72  208.58 Sacred secrets from the past
 208.58  212.70 Hear their voice, sharing their yearning
 212.70  216.54 Deep, deep, deep into you
 216.54  220.94 Hear their voice, sharing their memories
 220.94  224.54 Sacred secrets from the past
 224.54  226.36 The light
```
## The_Rinn_-_Voices__2017_Version_.mc0
```
   0.00   29.98 Thank you very much.
  30.00   56.48 The Sun Is Fading
  56.48   58.26 Under Blood Red Sky
  58.26   59.54 The Rain Of Day
  59.54   61.96 It is over
  61.96   66.12 Night soon will break free
  66.12   69.88 They wake in the eerie glow of moonlight
  69.88   74.18 Forgotten souls beyond our sight
  74.18   78.00 World has gone forever long ago
  78.00   81.04 Lost in the rise, the shine
  81.04   83.38 We've missed, we've lost
  83.38   86.22 Remaining shadows of lost time
  86.22   90.24 Whispering they are all right
  90.24   95.88 So bright you're waking in the morning
  95.88  100.40 Can't understand your feelings
 100.40  104.32 And where do you get these thoughts?
 104.70  107.62 Inside your mind a voice is calling
 107.62  111.92 For the night to rise at your side
 111.92  116.04 Our world has come forever long ago
 116.04  120.68 Lost in the rays that shine with mystery
 120.68  124.20 Lost we may in the shadows of our time
 124.20  127.70 Whispering their own lie
 127.70  132.82 So hear their voice, sharing their yearning
 132.82  136.54 Give their keeping to you
 136.54  140.64 Hear their voice, sharing their memories
 140.64  145.60 Sacred secrets from past time
 145.60  175.58 guitar solo
 175.60  181.32 A world that's gone forever, long ago, lost to the light
 181.32  186.86 There, shined with mystery, lost, remained in shadows
 186.86  191.08 All lost time, whispering in the moonlight
 191.08  196.78 So hear their voice, sharing their yearning
 196.78  200.46 Deep, deep, deep into you
 200.46  204.78 Hear their voice, sharing their memories
 204.78  208.58 Sacred secrets from past
 208.58  212.64 Hear their voice, sharing their glory
 212.64  216.54 Deep they give into you
 216.54  218.68 Hear their voice
 218.68  224.62 Sacred secrets from past
 224.62  226.36 Tide
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
 110.00  120.00 ♪♪♪
 120.00  122.00 ♪♪♪
 122.00  128.00 ♪♪♪
 128.00  130.00 ♪♪♪
 130.00  132.00 ♪♪♪
 132.00  134.00 ♪♪♪
 134.00  136.00 ♪♪♪
 136.00  138.00 ♪♪♪
 138.00  140.00 ♪♪♪
 140.00  150.00 ♪♪♪
 150.00  160.00 ♪♪♪
 160.00  166.00 ♪♪♪
 166.00  168.00 ♪♪♪
 168.00  170.00 ♪♪♪
 170.00  180.00 ♪♪♪
 180.00  182.00 ♪♪♪
 182.00  184.00 ♪♪♪
 184.00  186.00 ♪♪♪
 186.00  188.00 ♪♪♪
 188.00  190.00 ♪♪♪
 190.00  192.00 ♪♪♪
 192.00  194.00 ♪♪♪
 194.00  196.00 ♪♪♪
 196.00  198.00 ♪♪♪
 198.00  208.00 ♪♪♪
 208.00  210.00 ♪♪♪
 210.00  212.00 ♪♪♪
 212.00  218.00 ♪♪♪
 218.00  220.00 ♪♪♪
 220.00  222.00 ♪♪♪
 222.00  224.00 ♪♪♪
 224.00  226.00 ♪♪♪
 226.00  228.00 ♪♪♪
 228.00  228.62 you
```
