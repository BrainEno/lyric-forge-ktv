# Qwen3-ASR loop experiment

| model | song | config | exit | s | max_new_tokens | chunks | lines (ref) | words (ref) | WER | words outside sung lines | longest block loop | longest chunk raw chars |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0.6B | Avercage_-_Embers | chunk60 | 0 | 207 | 608 | 5 | 20 (42) | 98 (189) | 0.85 | 7 | - | 227 |
| 0.6B | Avercage_-_Embers | chunk60 | 0 | 256 | 608 | 5 | 40 (42) | 134 (189) | 0.71 | 16 | - | 267 |
| 0.6B | Avercage_-_Embers | chunk30 | 0 | 152 | 368 | 8 | 24 (42) | 105 (189) | 0.86 | 8 | 2x1@0s | 182 |
| 0.6B | Avercage_-_Embers | chunk30_noctx | 0 | 176 | 368 | 8 | 30 (42) | 140 (189) | 0.73 | 6 | - | 173 |
| 0.6B | Avercage_-_Embers.gated | chunk60 | 0 | 209 | 608 | 5 | 16 (42) | 77 (189) | 0.86 | 3 | - | 202 |
| 0.6B | Avercage_-_Embers.gated | chunk60 | 0 | 250 | 608 | 5 | 36 (42) | 124 (189) | 0.78 | 3 | - | 253 |
| 0.6B | Avercage_-_Embers.gated | chunk30 | 0 | 359 | 368 | 9 | 27 (42) | 100 (189) | 0.85 | 14 | - | 939 |
| 0.6B | Avercage_-_Embers.gated | chunk30_noctx | 0 | 176 | 368 | 9 | 31 (42) | 136 (189) | 0.72 | 2 | 3x1@213s | 169 |
| 0.6B | Kinematic_-_Peyote | chunk60 | 0 | 179 | 608 | 3 | 20 (14) | 147 (147) | 0.33 | 2 | - | 353 |
| 0.6B | Kinematic_-_Peyote | chunk60 | 0 | 271 | 608 | 3 | 22 (14) | 148 (147) | 0.28 | 4 | - | 359 |
| 0.6B | Kinematic_-_Peyote | chunk30 | 0 | 125 | 368 | 6 | 27 (14) | 146 (147) | 0.24 | 14 | - | 228 |
| 0.6B | Kinematic_-_Peyote | chunk30_noctx | 0 | 137 | 368 | 6 | 27 (14) | 148 (147) | 0.23 | 18 | - | 227 |
| 0.6B | Kinematic_-_Peyote.gated | chunk60 | 0 | 179 | 608 | 3 | 20 (14) | 135 (147) | 0.27 | 7 | - | 336 |
| 0.6B | Kinematic_-_Peyote.gated | chunk60 | 0 | 217 | 608 | 3 | 25 (14) | 141 (147) | 0.20 | 10 | - | 345 |
| 0.6B | Kinematic_-_Peyote.gated | chunk30 | 0 | 134 | 368 | 7 | 30 (14) | 149 (147) | 0.29 | 8 | - | 190 |
| 0.6B | Kinematic_-_Peyote.gated | chunk30_noctx | 0 | 153 | 368 | 7 | 29 (14) | 148 (147) | 0.28 | 7 | - | 194 |
| 0.6B | Ridgway_-_Fire_Inside | chunk60 | 0 | 388 | 608 | 5 | 34 (50) | 282 (304) | 0.31 | 2 | - | 504 |
| 0.6B | Ridgway_-_Fire_Inside | chunk60 | 0 | 365 | 608 | 5 | 39 (50) | 286 (304) | 0.18 | 1 | - | 474 |
| 0.6B | Ridgway_-_Fire_Inside | chunk30 | 0 | 229 | 368 | 10 | 45 (50) | 273 (304) | 0.35 | 29 | - | 332 |
| 0.6B | Ridgway_-_Fire_Inside | chunk30_noctx | 1 | 265 | 368 | 10 | 0 (50) | 0 (304) | - | 0 | - | 332 |
| 0.6B | Ridgway_-_Fire_Inside.gated | chunk60 | 0 | 363 | 608 | 5 | 35 (50) | 253 (304) | 0.36 | 0 | - | 498 |
| 0.6B | Ridgway_-_Fire_Inside.gated | chunk60 | 0 | 411 | 608 | 5 | 34 (50) | 270 (304) | 0.32 | 0 | - | 484 |
| 0.6B | Ridgway_-_Fire_Inside.gated | chunk30 | 0 | 204 | 368 | 10 | 39 (50) | 264 (304) | 0.37 | 14 | - | 286 |
| 0.6B | Ridgway_-_Fire_Inside.gated | chunk30_noctx | 0 | 231 | 368 | 10 | 37 (50) | 254 (304) | 0.37 | 4 | - | 286 |
| 0.6B | Songwriterz_-_Back_In_Time | chunk60 | 0 | 256 | 608 | 4 | 34 (46) | 234 (238) | 0.53 | 1 | - | 452 |
| 0.6B | Songwriterz_-_Back_In_Time | chunk60 | 0 | 352 | 608 | 4 | 49 (46) | 278 (238) | 0.43 | 7 | 2x1@62s | 444 |
| 0.6B | Songwriterz_-_Back_In_Time | chunk30 | 0 | 170 | 368 | 7 | 37 (46) | 296 (238) | 0.54 | 2 | - | 287 |
| 0.6B | Songwriterz_-_Back_In_Time | chunk30_noctx | 0 | 197 | 368 | 7 | 36 (46) | 297 (238) | 0.54 | 2 | - | 287 |
| 0.6B | The.madpix.project_-_One_Way_Street | chunk60 | 0 | 184 | 608 | 3 | 19 (30) | 132 (183) | 0.53 | 7 | - | 389 |
| 0.6B | The.madpix.project_-_One_Way_Street | chunk60 | 0 | 233 | 608 | 3 | 27 (30) | 182 (183) | 0.14 | 5 | - | 477 |
| 0.6B | The.madpix.project_-_One_Way_Street | chunk30 | 0 | 139 | 368 | 6 | 25 (30) | 189 (183) | 0.22 | 5 | - | 346 |
| 0.6B | The.madpix.project_-_One_Way_Street | chunk30_noctx | 0 | 161 | 368 | 6 | 24 (30) | 181 (183) | 0.25 | 4 | - | 345 |
| 0.6B | The_Rinn_-_Voices__2017_Version_ | chunk60 | 0 | 202 | 608 | 4 | 17 (46) | 140 (203) | 0.66 | 0 | - | 285 |
| 0.6B | The_Rinn_-_Voices__2017_Version_ | chunk60 | 0 | 346 | 608 | 4 | 38 (46) | 200 (203) | 0.52 | 8 | - | 555 |
| 0.6B | The_Rinn_-_Voices__2017_Version_ | chunk30 | 0 | 163 | 368 | 8 | 29 (46) | 199 (203) | 0.51 | 11 | - | 256 |
| 0.6B | The_Rinn_-_Voices__2017_Version_ | chunk30_noctx | 0 | 193 | 368 | 8 | 31 (46) | 199 (203) | 0.52 | 12 | - | 259 |

## Averages

| model | config | runs | mean WER | words outside sung lines | lines / ref lines |
|---|---|---|---|---|---|
| 0.6B | chunk60 | 18 | 0.458 | 83 | 525/668 |
| 0.6B | chunk30 | 9 | 0.469 | 105 | 283/334 |
| 0.6B | chunk30_noctx | 8 | 0.455 | 55 | 245/284 |

## Raw chunk outputs (first 600 chars)

### asr Avercage_-_Embers chunk60
- chunk @0.0s len 57.9s chars 144: `"Embers. Artist: Avercage. We don't understand. We don't know. We really carry the torch. Now we find. Now we know where we are. We don't know."`
- chunk @57.9s len 55.4s chars 227: `"For the moment, we are in the same eternal day. One day, oh, we can forever, we can forever, forever, forever, we can forever, we can forever. Just sit and watch, enjoy the sunset. Hey, hey, what you want? Just wait and wait."`
- chunk @113.3s len 60.8s chars 152: `"Embers. Artist: Avercage. One day long, we'll come forever, we'll come forever. Don't close your eyes, we'll come forever, we'll come forever. Embers."`
- chunk @174.1s len 64.1s chars 27: `"Embers. Artist: Avercage."`
- chunk @238.1s len 4.4s chars 26: `"Embers. Artist: Avercage"`

### asr Avercage_-_Embers.gated chunk60
- chunk @0.0s len 57.9s chars 175: `"Embers. Artist: Avercage. We don't dance, continue starting fires. We don't know when you're carrying the torch. Now we start, now we don't know where we are. We don't know."`
- chunk @57.9s len 55.4s chars 61: `"We'll come forever, forever. Just breathe forever, forever."`
- chunk @113.3s len 55.1s chars 27: `"Embers. Artist: Avercage."`
- chunk @168.4s len 64.2s chars 202: `"Embers. Artist: Avercage. One day you'll go forever, go forever. Don't close your eyes, go forever, go forever. Forever, forever, never stop. Once in the end, the flames return, believing in the past."`
- chunk @232.6s len 9.9s chars 26: `"Embers. Artist: Avercage"`

### asr Kinematic_-_Peyote chunk60
- chunk @0.0s len 64.5s chars 308: `"I'm asleep on the wheel and there's a car in the highway. Yet we tend through the night like a bee out of my wing. How much better is it? Aching so exquisite. I hope we can stop inside. Now you don't want to turn to look right through you. Oh, oh, oh, and the clothes that you wear. We don't need to stand."`
- chunk @64.5s len 59.1s chars 353: `"Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing. How much fun that is—it's ancient, so exquisite. I hope we can stop being tired. Now you don't want to turn because look around for you. Oh, and the clothes that you wear would tell me to stand. Oh, but the people you know—they say what they want to."`
- chunk @123.6s len 59.8s chars 81: `"Oh, oh, oh, because a true lover is—we don't really care. That's quite another."`

### asr Kinematic_-_Peyote.gated chunk60
- chunk @0.0s len 64.9s chars 296: `"I'm asleep on the wheel and there's a car in the highway. Yet we turn through the night like a peyote migraine. How much farther is it? Aching so exquisite. I hope we can stop inside. Now you don't want to dance to look right through you. Oh, I'm the ghost that you are. We don't need to stand."`
- chunk @64.9s len 58.7s chars 336: `"Now the sky is on fire and the desert is freezing. Wonder how I'll live when I'm not even breathing. How much better is it? Aching so exquisite. I hope we can stop in time. Now you don't wanna dance 'cause look around you. Oh, and the clothes that you wear with no way to stand. Oh, but the people you know. Let's say what we want to."`
- chunk @123.6s len 59.8s chars 49: `"Oh, because we're lovers, we don't really care."`

### asr Ridgway_-_Fire_Inside chunk60
- chunk @0.0s len 60.2s chars 239: `"I got a lot on my mind and all of the time we're trying to do right. I may have lost a life, but I'm keeping it tight. Never give the final. When my life is over, when my life is over, got to keep it on and check. I keep it on and check."`
- chunk @60.2s len 60.9s chars 387: `"Even in the darkest days, got a trail to blaze gonna stick to my ways. I used to be caught in a face where life was a maze until the sun's rays. When your life is so rich, you got to take the first step. Yeah, oh oh oh oh oh. Headlong through the waves now. Oh oh oh oh oh. Gonna take me to that place. Oh oh oh oh oh. On that fire inside. Oh oh oh oh oh. It's a faith that you decide."`
- chunk @121.0s len 60.7s chars 504: `"When I feel like I'm losing control, gotta reach within my soul. And if you ever feel it low, yeah, you gotta take the first step. And girl, yeah, take that first step to the right. Gotta find what's inside. Before we run out of time, run out of time, run out of time. Whoa, whoa, whoa, whoa, whoa. I'll run through the waves now. Whoa, whoa, whoa, whoa, whoa. Gonna take me to that place. Whoa, whoa, whoa, whoa, whoa. Find that fire inside. Whoa, whoa, whoa, whoa, whoa. It's a faith that you decide."`
- chunk @181.7s len 55.5s chars 14: `"Fire Inside."`
- chunk @237.2s len 46.8s chars 218: `"Oh, I'm battling on, I'm battling strong. Find the fire, find the fire. Oh, oh, oh, oh. I'm battling on, I'm battling strong. Oh, oh, oh, oh. Find the fire, find the fire. Find the fire. Find the fire. Find the fire."`

### asr Ridgway_-_Fire_Inside.gated chunk60
- chunk @0.0s len 63.3s chars 239: `"I got a lot on my mind and all of the time we're trying to do right. I may have lost a life, but I'm keeping it tight. Never give the final. When my life is over, when my life is over, got to keep it all in check. I keep it all in check."`
- chunk @63.3s len 57.7s chars 332: `"Even in the darkest days, got a trail to blaze gonna stick to my waist. I used to be caught in a phase where life was a maze until I saw the sun's rays. When your life is so red, you got to take the first step. Yeah, had longed through the waves now. Gonna take me to that place. Find the fire inside. It's a fate that you decide."`
- chunk @121.0s len 60.7s chars 498: `"When I feel like I'm losing control, gotta reach within my soul. And if you ever feel low, yeah, you gotta take the first step. And girl, yeah, take that first step to the right. Got to find what's inside. But we run out of time, run out of time, run out of time. Whoa, whoa, whoa, whoa, whoa. Headlong through the waves now. Whoa, whoa, whoa, whoa, whoa. Gonna take me to that place. Whoa, whoa, whoa, whoa, whoa. Find that fire inside. Whoa, whoa, whoa, whoa, whoa. It's a fate that you decide."`
- chunk @181.7s len 55.5s chars 21: `"That you disappear."`
- chunk @237.2s len 46.8s chars 167: `"I'm battling on, I'm battling strong. Find the fire, find the fire. I'm battling on, I'm battling strong. Find the fire, find the fire. Find the fire, find the fire."`

### asr Songwriterz_-_Back_In_Time chunk60
- chunk @0.0s len 58.9s chars 452: `"Honey, I told you something. Sorry, I didn't hear. Maybe there are something. Yeah, yeah, yeah, stuck in your ear. Why is it every time you say you do you don't? Maybe I just thought that you were talking on the phone. Honey, you look lovely tonight. Sorry, you wasting time. Maybe they see you looking nice. Well, try and ain't a cry. Why is it every time I like to do you don't? Maybe you could try a little romance and come. Let's go back in time."`
- chunk @58.9s len 63.8s chars 431: `"We'd lie when we were la la la la la la la la la la. It's memory light and the daily strife to be la la la la la la la la la la. Honey, get older. Yeah, you're still twenty-nine. And baby, things are colder. But honey, you still you're mine. Gets it easy to forget the moment away. Could it be that la la la, you keep the love alive? Let's go back in time. We'd lie when we were la la la la la la la la la la. But when you and I."`
- chunk @122.7s len 56.2s chars 307: `"Still had time to be la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la la"`
- chunk @178.9s len 30.1s chars 160: `"Back in time, we never will. We will la la la la la la la la la. Now it's not real life, still we have to try to be la la la la la la la la la la la la la la."`

### asr The.madpix.project_-_One_Way_Street chunk60
- chunk @0.0s len 64.9s chars 389: `"One Way Street. Years I like diamonds in my eyes, like me so now you're out of sight. It's enough. It's too late to break this silence. In a rose colored view of us, I got lost. Could I realize all your lies would be black nights? Just let me inside. I'll save you from the dark. I will fix your selfish heart. A One Way Street. That's how you leave. Why do you always take the negative?"`
- chunk @64.9s len 59.8s chars 166: `"One Way Street. Artist: The.Madpix.Project. Why do you always take a never leave? I walk away to help you see. Our love is rolling down so easily. A one way street."`
- chunk @124.7s len 46.3s chars 121: `"One Way Street. One Way Street. You never give. One Way Street. I walk away. One Way Street. So easily. One Way Street."`

### asr The_Rinn_-_Voices__2017_Version_ chunk60
- chunk @0.0s len 62.5s chars 65: `"The sun is fading under blood red sky. The rain of day is over."`
- chunk @62.5s len 57.9s chars 171: `"Now it will break free. They wake in the eerie glow of moonlight. The stars beyond our sight. We'll escape forever. All at dawn. Lost in the rise, the shine. We'll miss."`
- chunk @120.4s len 59.6s chars 229: `"We lost in the shadows of our time. Whispering there will lie. Don't hear the voice sharing the journey. Keep it deep into you. Hear the voice sharing the memories. Say that secrets are lost time. We were lost forever long ago."`
- chunk @180.0s len 51.2s chars 285: `"The sound we miss, we lost, we made shadows on our side. Whispering the world lies. So hear the voice sharing the garden. Keep it keeping to you. Hear the voice sharing the memories. Secret secrets from past. Hear the voice sharing the garden. Keep it keeping to you. Hear the voice."`

### asr Avercage_-_Embers chunk30
- chunk @0.0s len 31.3s chars 26: `"Embers. Artist: Avercage"`
- chunk @31.3s len 33.9s chars 182: `"Embers. Artist: Avercage. We don't know when you'll carry me to the end. There will be sparks. There will be it all. When we are apart, we don't know for the moment when we'll die."`
- chunk @65.2s len 29.6s chars 27: `"Embers. Artist: Avercage."`
- chunk @94.8s len 34.3s chars 139: `"Just read the book. The story of the gods and the gods. The book of the gods. Nothing in the dark of the night. Nothing. One day you can."`
- chunk @129.0s len 27.4s chars 78: `"Forever, oh come forever, close your eyes. Oh come forever, oh come forever."`
- chunk @156.4s len 32.8s chars 37: `"Embers. Avercage. Ah, darkness. Ah."`
- chunk @189.2s len 25.2s chars 26: `"Embers. Artist: Avercage"`
- chunk @214.4s len 28.1s chars 80: `"Never, never, never. Once in the end, the flame burns, but living never burns."`

### asr Avercage_-_Embers.gated chunk30
- chunk @0.0s len 31.3s chars 26: `"Embers. Artist: Avercage"`
- chunk @31.3s len 33.9s chars 146: `"Embers. Artist: Avercage. We don't know when you'll carry the torch. There will be no where we are. We don't know for the moment when we'll die."`
- chunk @65.2s len 29.6s chars 27: `"Embers. Artist: Avercage."`
- chunk @94.8s len 34.3s chars 939: `"Just keep burning, just keep burning. Hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, hot, h`
- chunk @129.0s len 27.3s chars 81: `"Forever, oh God forever, don't close your eyes. Oh God forever, oh God forever."`
- chunk @156.3s len 25.2s chars 27: `"Embers. Artist: Avercage."`
- chunk @181.5s len 28.0s chars 112: `"Embers. Artist: Avercage. One day you'll go forever, go forever. Don't lose your eyes, go forever, go forever."`
- chunk @209.5s len 31.6s chars 110: `"Never burn, burn, burn, burn, burn. Never burn, once in the end. The flame will burn, but leave in the dust."`
- chunk @241.1s len 1.5s chars 27: `"Embers. Artist: Avercage."`

### asr Kinematic_-_Peyote chunk30
- chunk @0.0s len 34.7s chars 115: `"I'm asleep on the wheel, and there's a car in the highway. Yet we tear through the night like a peyote microwave."`
- chunk @34.7s len 33.2s chars 183: `"How much fun that is—it's aching so exquisite. I hope we can stop it. Now you don't want to dance. You're looking like you. Oh, and the clothes that you wear—we don't need to stare."`
- chunk @68.0s len 33.2s chars 179: `"Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing. How much fire that is? It's aching so exquisite. I hope we can stop in time."`
- chunk @101.2s len 33.1s chars 228: `"Now you don't want to dance, cause we look around for you. Oh, and the clothes that you wear, we don't need to stare. Oh, but the people you know, they say what they want to. Oh, cause the truth of it is, we don't really care."`
- chunk @134.3s len 25.5s chars 9: `"Peyote."`
- chunk @159.8s len 23.5s chars 30: `"That's quite enough of that."`

### asr Kinematic_-_Peyote.gated chunk30
- chunk @0.0s len 29.2s chars 60: `"I'm asleep on the wheel, and there's a car in the highway."`
- chunk @29.2s len 29.9s chars 190: `"Yet we tap through the night like a piece of your mind. How much better is it? Aching so exquisite. I hope we can stop inside. Now you don't want to dance. So look a light through you. Oh."`
- chunk @59.0s len 28.1s chars 153: `"And the clothes that you wear with only two steps. Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing."`
- chunk @87.2s len 28.9s chars 188: `"How much better is it? Aching so exquisite. I hope we can stop in time. Now you don't want to dance, cause look around for you. Oh, and the clothes that you wear, we don't need to stare."`
- chunk @116.0s len 25.7s chars 110: `"Oh, but the people you know—they say what they want to. Oh, because the truth of it is we don't really care."`
- chunk @141.7s len 34.7s chars 27: `"Peyote. Artist: Kinematic"`
- chunk @176.4s len 7.0s chars 28: `"That's quite a move. That."`

### asr Ridgway_-_Fire_Inside chunk30
- chunk @0.0s len 25.5s chars 31: `"Fire Inside. Artist: Ridgway."`
- chunk @25.5s len 34.7s chars 249: `"I got a lot on my mind and all of the time we're trying to do right. I may have lost a life, but I'm keeping it tight. Never give the final. When my life was so right, when my life was so right. Got to keep it on and check. I keep it on and check."`
- chunk @60.2s len 34.6s chars 276: `"Even in the darkest days, got a trail to blaze gonna stick to my ways. I used to be caught in a phase where life was a maze until I saw the sun's rays. When your life is so rich, you got to take the first step. Yeah, whoa, oh, oh, oh, oh. I've learned through the waves now."`
- chunk @94.8s len 34.7s chars 101: `"Whoa, gonna take me to that place. Whoa, find that fire inside. Whoa, it's a faith that you decide."`
- chunk @129.5s len 34.3s chars 332: `"When I feel like I'm losing control, gotta reach within my soul. And if you ever feel it low, yeah, you gotta take the first step. And girl, yeah, take that first step to the right. Got to find what's inside. Before we run out of time, run out of time, run out of time. Whoa, oh, oh, oh, oh, I've been alone through the waves now."`
- chunk @163.8s len 25.0s chars 117: `"Whoa, gonna take me to that place. Whoa, find that fire inside. Whoa, it's a fate that you decide. That you decide."`
- chunk @188.8s len 34.6s chars 30: `"Fire Inside. Artist: Ridgway"`
- chunk @223.4s len 28.4s chars 99: `"Whoa, I'm feeling on, I'm feeling strong. Whoa, I'm the fire, I'm the fire. Whoa, I'm feeling on."`
- chunk @251.8s len 31.6s chars 91: `"I'm petrified. Find the fire. Find the fire. Find the fire. Find the fire. Find the fire."`
- chunk @283.4s len 0.5s chars 43: `"Song title: Fire Inside. Artist: Ridgway."`

### asr Ridgway_-_Fire_Inside.gated chunk30
- chunk @0.0s len 25.4s chars 30: `"Fire Inside. Artist: Ridgway"`
- chunk @25.4s len 34.7s chars 237: `"I got a lot of my mind in all of the time, but trying to do right. I may have lost a life, but I'm keeping it tight. Never give the final. When my life is over, when my life is over, got to keep it on and check. I keep it on and check."`
- chunk @60.2s len 34.6s chars 253: `"Even in the darkest days, got a trail to blaze gonna stick to my ways. I used to be caught in a phase where life was a maze until I saw the sun's rays. When your life is a race, you got to take the first step. Whoa, I've learned through the waves now."`
- chunk @94.8s len 26.2s chars 101: `"Whoa, gonna take me to that place. Whoa, find that fire inside. Whoa, it's a faith that you decide."`
- chunk @121.0s len 32.9s chars 210: `"When I feel like I'm losing control, gotta reach within my soul. And if you ever feel it low, yeah, you gotta take the first step, and girl, yeah, take that first step to the right. Got to find what's inside."`
- chunk @153.9s len 33.7s chars 286: `"But we run out of time, run out of time, run out of time. Whoa, whoa, whoa, whoa. Headlong through the waves now. Whoa, whoa, whoa, whoa. Gonna take me to that place. Whoa, whoa, whoa, whoa. Find that fire inside. Whoa, whoa, whoa, whoa. It's a faith that you decide. That you decide."`
- chunk @187.6s len 32.8s chars 30: `"Fire Inside. Artist: Ridgway"`
- chunk @220.4s len 31.4s chars 83: `"I'm feeling on. I'm feeling strong. Find the fire. Find the fire. I'm feeling on."`
- chunk @251.8s len 30.8s chars 76: `"I'm petrified. Find the fire. Find the fire. Find the fire. Find the fire."`
- chunk @282.6s len 1.4s chars 31: `"Fire Inside. Artist: Ridgway."`

### asr Songwriterz_-_Back_In_Time chunk30
- chunk @0.0s len 26.3s chars 164: `"Honey, I told you something. Sorry, I didn't hear. Maybe there is something. Yeah, yeah, yeah, stuck in your ear. Why you say every time you say you do you don't."`
- chunk @26.3s len 32.6s chars 287: `"Maybe I just thought that you were talking on the phone. Honey, you look lovely tonight. Sorry, you're wasting time. Maybe this is your lucky night. Well, trying ain't a crime. Why is it every time I like to do you don't? Maybe you could try a little Romanesque. Let's go back in time."`
- chunk @58.9s len 31.1s chars 208: `"Way the way we were, la la la la la la la la la. La, it's memory light and the daily strife to be, la la la la la la la la la. La la la la la la la la la la la la la la. Honey, get no doubt. Yeah, years to."`
- chunk @90.1s len 32.6s chars 261: `"Twenty nine, and maybe things are colder, but only you still your mind. Guess it's easy to forget the more the man away. Could it be that love magic keeping love alive? Let's go back in time, way back when we were la la la la la la la la. Back when you and I."`
- chunk @122.7s len 34.7s chars 71: `"Still had time to be la la la la la la la la la la la la la la la la."`
- chunk @157.4s len 30.6s chars 212: `"Let's go back in time. Way back when we were la la la la la la la la la. Back when you and I still had time to feel la la la la la la la la. Let's go back in time. Way back when we were la la la la la la la la."`
- chunk @187.9s len 21.1s chars 91: `"Now it's Mary life. We have to try to be la la la la la la la la la la la la la la la la."`

### asr The.madpix.project_-_One_Way_Street chunk30
- chunk @0.0s len 34.0s chars 193: `"One Way Street. Tears like diamonds in my eyes, like me so. Now you're out of sight. It's enough. It's too late to break this silence. In a rose-colored view of us, I got lost. Could I reach."`
- chunk @34.0s len 30.9s chars 216: `"All your lies, all your lies would be blades and knives. Just tap me inside. I will save you from the dark. I will fix your selfish heart. A one way street. It's how you live. Why do you always take and never give?"`
- chunk @64.9s len 27.9s chars 128: `"Wide awake, yeah I've crossed the line. I'm coming home, I'm running back to real life, to the start where I could breathe in."`
- chunk @92.8s len 31.9s chars 346: `"Freelee baby, can you see we run out of time chasing happiness while you get what you need? There's nothing left of us but bleeding blades of knives tonight. You'll know how it feels in one way street. That's how you leave. Why do you always take a never leave? I walk away to help you see our love is rolling down so easily. In one way street."`
- chunk @124.7s len 33.4s chars 20: `"At one way street."`
- chunk @158.1s len 12.9s chars 56: `"You never give. I walk away so easily. One way street."`

### asr The_Rinn_-_Voices__2017_Version_ chunk30
- chunk @0.0s len 30.4s chars 9: `"Voices."`
- chunk @30.4s len 32.1s chars 66: `"The sun is fading under blood red sky. The reign of day is over."`
- chunk @62.5s len 28.5s chars 251: `"Night, so we'll break free. They wake in the eerie glow of moonlight. Forgotten souls beyond our sight. World is gone forever. All that's gone was in the eyes that shine. We miss we lost we made each other's last night. Whispering there would light."`
- chunk @91.0s len 29.4s chars 256: `"Surprise! You're waking in the morning. Can't understand your feelings. And when you get these thoughts inside your mind, the voice calling for the night to rise at your side. Oh, love, the sun forever morning. Lost in the night, the light shine with me."`
- chunk @120.4s len 28.4s chars 198: `"We lost, we made shadows. Upside, whisper you there would lie. Don't hear the voice sharing the yearning, keep it deep into you. Hear the voice sharing the memories, sacred secrets from past time."`
- chunk @148.8s len 31.2s chars 43: `"World gets drunk forever. A lot of girls."`
- chunk @180.0s len 27.6s chars 214: `"The sound we missed, we lost, we made in shadows of our sight. Whispering the old lies. So hear the voice sharing the gunning, keep them keeping to you. Hear the voice sharing the memories, secrets, secrets from."`
- chunk @207.6s len 23.6s chars 75: `"Hear the voice sharing the garden, keep it giving to you. Hear the voice."`

### asr Avercage_-_Embers chunk30_noctx
- chunk @0.0s len 31.3s chars 6: `"The."`
- chunk @31.3s len 33.9s chars 173: `"You can't just continue starting fights where we don't know. When you leave, carry the torch. There will be no where we are. We don't know for the moment when we will die."`
- chunk @65.2s len 29.6s chars 140: `"Fade into the dust of a long day. One day long, but can't forever, can't forever. Don't close your eyes, but can't forever, can't forever."`
- chunk @94.8s len 34.3s chars 129: `"Just fit for the joy of the gods. Hey, you are the perfect man. Nothing in the dark of the night. Nothing. One day you'll come."`
- chunk @129.0s len 27.4s chars 78: `"Forever, oh come forever, close your eyes. Oh come forever, oh come forever."`
- chunk @156.4s len 32.8s chars 26: `"And you are the promise."`
- chunk @189.2s len 25.2s chars 132: `"Wonderful, oh God, forever, oh God, forever, don't close your eyes, oh God, forever, oh God, forever, don't stop, oh God, forever."`
- chunk @214.4s len 28.1s chars 85: `"Never, never stop. I've seen the end. The flame is burning, but living never stops."`

### asr Avercage_-_Embers.gated chunk30_noctx
- chunk @0.0s len 31.3s chars 6: `"The."`
- chunk @31.3s len 33.9s chars 169: `"You can't just continue starting fights where we don't know. We really can't reach Juliet. There will be no where we are. We don't know for the moment when we are not."`
- chunk @65.2s len 29.6s chars 140: `"Fade into the dust of a long day. One day long, but can't forever, can't forever. Don't close your eyes, but can't forever, can't forever."`
- chunk @94.8s len 34.3s chars 146: `"Just keep on going, don't stop. Don't stop. Hey, you are the one who burns my heart. Nothing in the dark can make me lonely. One day, I'll come."`
- chunk @129.0s len 27.3s chars 81: `"Forever, oh God forever, don't close your eyes. Oh God forever, oh God forever."`
- chunk @156.3s len 25.2s chars 10: `"Promise."`
- chunk @181.5s len 28.0s chars 86: `"One day you'll go forever, go forever. Don't lose your eyes, go forever, go forever."`
- chunk @209.5s len 31.6s chars 106: `"Never more, never, never, never. Never, never, once in the end, the flame is rendered, but living never."`
- chunk @241.1s len 1.5s chars 7: `"Okay."`

### asr Kinematic_-_Peyote chunk30_noctx
- chunk @0.0s len 34.7s chars 118: `"I'm asleep at the wheel, and there's a car in the highway. Yet we tear through the night like a beat your microwave."`
- chunk @34.7s len 33.2s chars 181: `"How much better is it? Aching so exquisite. I hope we can stop it. Now you don't want to dance. You're looking like you. Oh, and the clothes that you wear. We don't need to stare."`
- chunk @68.0s len 33.2s chars 179: `"Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing. How much fire that is? It's aching so exquisite. I hope we can stop in time."`
- chunk @101.2s len 33.1s chars 227: `"Now you don't want to turn, cause we look around for you. Oh, and the clothes that you wear, we don't need to stare. Oh, but the people you know, they say what they want to. Oh, cause the truth of it is, we don't really care."`
- chunk @134.3s len 25.5s chars 5: `"Oh."`
- chunk @159.8s len 23.5s chars 30: `"That's quite enough of that."`

### asr Kinematic_-_Peyote.gated chunk30_noctx
- chunk @0.0s len 29.2s chars 60: `"I'm asleep on the wheel, and there's a car in the highway."`
- chunk @29.2s len 29.9s chars 194: `"Yet we tap through the night like a beat of your microwave. How much better is it? Aching so exquisite. I hope we can stop inside. Now you don't want to dance. So look at life through you. Oh."`
- chunk @59.0s len 28.1s chars 153: `"And the clothes that you wear with only two steps. Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing."`
- chunk @87.2s len 28.9s chars 188: `"How much better is it? Aching so exquisite. I hope we can stop in time. Now you don't want to dance, cause look around for you. Oh, and the clothes that you wear, we don't need to stare."`
- chunk @116.0s len 25.7s chars 110: `"Oh, but the people you know—they say what they want to. Oh, because the truth of it is we don't really care."`
- chunk @141.7s len 34.7s chars 8: `"Music."`
- chunk @176.4s len 7.0s chars 32: `"That's quite a matter of that."`

### asr Ridgway_-_Fire_Inside chunk30_noctx
```
o that place. Whoa, find that fire inside. Whoa, it's a faith that you decide."
LF_CHUNK	1	25.48	34.69	"I got a lot on my mind and all of the time we're trying to do right. I may have lost a life, but I'm keeping it tight. Never give the final. When my life was so right, when my life was so right. Got to keep it on and check. I keep it on and check."
LF_CHUNK	2	60.17	34.60	"Even in the darkest days, got a trail to blaze gonna stick to my ways. I used to be caught in a phase where life was a maze until I saw the sun's rays. When your life is so rich, you got to take the first step. Yeah, I've learned through the waves now."
LF_CHUNK	6	188.84	34.60	"Oh."
LF_CHUNK	4	129.47	34.34	"When I feel like I'm losing control, gotta reach within my soul. And if you ever feel it low, yeah, you gotta take the first step. And girl, yeah, take that first step to the right. Got to find what's inside. Before we run out of time, run out of time, run out of time. Whoa, oh, oh, oh, oh, I've been alone through the waves now."
LF_CHUNK	8	251.82	31.57	"I'm panic strung. Find the fire, find the fire, find the fire, find the fire, find the fire."
LF_CHUNK	7	223.44	28.37	"Whoa, I'm feeling on. I'm feeling strong. Whoa, I'm the fighter. I'm the fighter. Whoa, I'm feeling on."
LF_CHUNK	0	0.00	25.48	"Oh."
LF_CHUNK	5	163.81	25.04	"Whoa, gonna take me to that place. Whoa, find that fire inside. Whoa, it's a fate that you decide. That you decide."
LF_CHUNK	9	283.39	0.54	"."
Error: tokenized word_list is empty

```
- chunk @0.0s len 25.5s chars 5: `"Oh."`
- chunk @25.5s len 34.7s chars 249: `"I got a lot on my mind and all of the time we're trying to do right. I may have lost a life, but I'm keeping it tight. Never give the final. When my life was so right, when my life was so right. Got to keep it on and check. I keep it on and check."`
- chunk @60.2s len 34.6s chars 254: `"Even in the darkest days, got a trail to blaze gonna stick to my ways. I used to be caught in a phase where life was a maze until I saw the sun's rays. When your life is so rich, you got to take the first step. Yeah, I've learned through the waves now."`
- chunk @94.8s len 34.7s chars 101: `"Whoa, gonna take me to that place. Whoa, find that fire inside. Whoa, it's a faith that you decide."`
- chunk @129.5s len 34.3s chars 332: `"When I feel like I'm losing control, gotta reach within my soul. And if you ever feel it low, yeah, you gotta take the first step. And girl, yeah, take that first step to the right. Got to find what's inside. Before we run out of time, run out of time, run out of time. Whoa, oh, oh, oh, oh, I've been alone through the waves now."`
- chunk @163.8s len 25.0s chars 117: `"Whoa, gonna take me to that place. Whoa, find that fire inside. Whoa, it's a fate that you decide. That you decide."`
- chunk @188.8s len 34.6s chars 5: `"Oh."`
- chunk @223.4s len 28.4s chars 105: `"Whoa, I'm feeling on. I'm feeling strong. Whoa, I'm the fighter. I'm the fighter. Whoa, I'm feeling on."`
- chunk @251.8s len 31.6s chars 94: `"I'm panic strung. Find the fire, find the fire, find the fire, find the fire, find the fire."`
- chunk @283.4s len 0.5s chars 3: `"."`

### asr Ridgway_-_Fire_Inside.gated chunk30_noctx
- chunk @0.0s len 25.4s chars 6: `"The."`
- chunk @25.4s len 34.7s chars 237: `"I got a lot of my mind in all of the time, but trying to do right. I may have lost a life, but I'm keeping it tight. Never give the final. When my life is over, when my life is over, got to keep it on and check. I keep it on and check."`
- chunk @60.2s len 34.6s chars 253: `"Even in the darkest days, got a trail to blaze gonna stick to my ways. I used to be caught in a phase where life was a maze until I saw the sun's rays. When your life is a race, you got to take the first step. Whoa, I've learned through the waves now."`
- chunk @94.8s len 26.2s chars 101: `"Whoa, gonna take me to that place. Whoa, find that fire inside. Whoa, it's a faith that you decide."`
- chunk @121.0s len 32.9s chars 210: `"When I feel like I'm losing control, gotta reach within my soul. And if you ever feel it low, yeah, you gotta take the first step, and girl, yeah, take that first step to the right. Got to find what's inside."`
- chunk @153.9s len 33.7s chars 286: `"But we run out of time, run out of time, run out of time. Whoa, whoa, whoa, whoa. Headlong through the waves now. Whoa, whoa, whoa, whoa. Gonna take me to that place. Whoa, whoa, whoa, whoa. Find that fire inside. Whoa, whoa, whoa, whoa. It's a faith that you decide. That you decide."`
- chunk @187.6s len 32.8s chars 5: `"Oh."`
- chunk @220.4s len 31.4s chars 83: `"I'm pelting on. I'm pelting strong. Find the fire. Find the fire. I'm pelting on."`
- chunk @251.8s len 30.8s chars 63: `"I'm on the fire. Find the fire. Find the fire. Find the fire."`
- chunk @282.6s len 1.4s chars 7: `"Okay."`

### asr Songwriterz_-_Back_In_Time chunk30_noctx
- chunk @0.0s len 26.3s chars 164: `"Honey, I told you something. Sorry, I didn't hear. Maybe there is something. Yeah, yeah, yeah, stuck in your ear. Why you say every time you say you do you don't."`
- chunk @26.3s len 32.6s chars 287: `"Maybe I just thought that you were talking on the phone. Honey, you look lovely tonight. Sorry, you're wasting time. Maybe this is your lucky night. Well, crying ain't a crime. Why is it every time I like to do you don't? Maybe you could try a little Romanesque. Let's go back in time."`
- chunk @58.9s len 31.1s chars 205: `"Way that way we were, la la la la la la la la la. It's memory light and the daily strife to be, la la la la la la la la la. La la la la la la la la la la la la la la. Honey, get no doubt. Yeah, years to."`
- chunk @90.1s len 32.6s chars 261: `"Twenty nine, and maybe things are colder, but only you still your mind. Guess it's easy to forget the more the man away. Could it be that love magic keeping love alive? Let's go back in time, way back when we were la la la la la la la la. Back when you and I."`
- chunk @122.7s len 34.7s chars 71: `"Still had time to be la la la la la la la la la la la la la la la la."`
- chunk @157.4s len 30.6s chars 216: `"Let's go back in time, way back when. We were la la la la la la la la la. Back when you and I still had time to feel la la la la la la la la. Let's go back in time, way back when we were la la la la la la la la la."`
- chunk @187.9s len 21.1s chars 96: `"Now it's Mary life for you. We have to try to be la la la la la la la la la la la la la la la."`

### asr The.madpix.project_-_One_Way_Street chunk30_noctx
- chunk @0.0s len 34.0s chars 173: `"Ears like diamonds in my eyes, like me so now you're out of sight. It's enough. It's too late to break this silence. In a rose-colored view of us, I got lost. Could I read"`
- chunk @34.0s len 30.9s chars 216: `"All your lies, all your lies would be blades and knives. Just tap me inside. I will save you from the dark. I will fix your selfish heart. A one-way street. It's how you live. Why do you always take and never give?"`
- chunk @64.9s len 27.9s chars 129: `"Wide awake, yeah, I've crossed the line. I'm coming home, I'm running back to real life, to the start where I could breathe in."`
- chunk @92.8s len 31.9s chars 345: `"Freelee baby, can you see we run out of time chasing happiness while you get what you need? There's nothing left of us but bleeding blades of knives tonight. You'll know how it feels in one way street. That's how you leave. Why do you always take a never leave? I walk away to help you see our love is rolling down so easily in one way street."`
- chunk @124.7s len 33.4s chars 20: `"At one-way street."`
- chunk @158.1s len 12.9s chars 40: `"You never give. I walk away so easily."`

### asr The_Rinn_-_Voices__2017_Version_ chunk30_noctx
- chunk @0.0s len 30.4s chars 6: `"The."`
- chunk @30.4s len 32.1s chars 66: `"The sun is fading under blood red sky. The reign of day is over."`
- chunk @62.5s len 28.5s chars 250: `"Night, so we'll break free. They wake in the eerie glow of moonlight. Forgotten shadows beyond our sight. World is gone forever. All that's gone was in the eyes that shine. We miss we lost we made each other's last night. Whispering they will rise."`
- chunk @91.0s len 29.4s chars 259: `"It's bright. You're waking in the morning. Can't understand your feelings. And when you get these thoughts inside your mind, the voice calling for the night to rise at your side. Oh, love, the sun forever morning. Lost in the night, the light shine with me."`
- chunk @120.4s len 28.4s chars 198: `"We lost, we made shadows. Upside, whisper you there would lie. Don't hear the voice sharing the yearning, keep it deep into you. Hear the voice sharing the memories, sacred secrets from past time."`
- chunk @148.8s len 31.2s chars 41: `"World gets gone forever. A lot of gold."`
- chunk @180.0s len 27.6s chars 214: `"The shine we missed, we lost, we made in shadows of our sight. Whispering the old lies. So hear the voice sharing the gunning, keep them keeping to you. Hear the voice sharing the memories, secrets, secrets from."`
- chunk @207.6s len 23.6s chars 74: `"Hear the voice sharing the agony, keeping it within you. Hear the voice."`

### asr Avercage_-_Embers chunk60
- chunk @0.0s len 57.9s chars 144: `"The thunderous continuing stormheads must wear. We don't know when it will carry it to the end. Never expect, never be nowhere. We don't know."`
- chunk @57.9s len 55.4s chars 267: `"For the moment, we feel alive. No matter the danger, don't let go. One day it all will come forever, will come forever. Don't close your eyes, will come forever, will come forever. Just keep on dancing, till you pass the goal. Hey, hey, my love, keep on running on."`
- chunk @113.3s len 60.8s chars 105: `"Embers. One day it'll be gone forever, gone forever. The glow of your eyes, gone forever, gone forever."`
- chunk @174.1s len 64.1s chars 217: `"So I promise. Oh, one day I'll go forever, I'll go forever. Don't lose your voice. I'll go forever, I'll go forever. Never stop, never stop, never stop. Once in the end, the flames burned out, but living never ends."`
- chunk @238.1s len 4.4s chars 9: `"Embers."`

### asr Avercage_-_Embers.gated chunk60
- chunk @0.0s len 57.9s chars 133: `"The thunderous continues to get smarter. We don't know when you'll carry it to the end. Never expect, never be open. We don't know."`
- chunk @57.9s len 55.4s chars 253: `"For the moments we feel alive, no matter the danger. One day it all will come forever, will come forever. Don't close your eyes, will come forever, will come forever. Just keep on dancing, till your body comes alive. Hey, are you ready for the moment?"`
- chunk @113.3s len 55.1s chars 105: `"Embers. One day it'll be gone forever, gone forever. The dark of your eyes, gone forever, gone forever."`
- chunk @168.4s len 64.2s chars 189: `"Embers. Oh, come on, brother, come on, brother, don't lose your voice. Oh, come on, brother, come on, brother, never stop. Don't see me here. The flames are there, but living never stops."`
- chunk @232.6s len 9.9s chars 27: `"Embers. Artist: Avercage."`

### asr Kinematic_-_Peyote chunk60
- chunk @0.0s len 64.5s chars 310: `"I'm asleep at the wheel and there's a car in the highway. Yet we tear through the night like a bee out of my brain. How much pain is it aching so exquisite? I hope we can stop it. So now you don't want to dance, but you're looking right through you. Oh, and the clothes that you wear, we don't need to stand."`
- chunk @64.5s len 59.1s chars 359: `"Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing. How much pain there is—it's aching so exquisite. I hope we can stop in time. Now you don't wanna dance 'cause they're looking right through you. Oh, and the clothes that you wear don't make you stand. Oh, but the people you know just say what they want to."`
- chunk @123.6s len 59.8s chars 83: `"Oh, doesn't you bother us? We don't really care. And that's quite enough of that."`

### asr Kinematic_-_Peyote.gated chunk60
- chunk @0.0s len 64.9s chars 307: `"I'm asleep at the wheel and as it comes in the highway. Yet we tear through the night like a peyote migraine. How much further is it aching so exquisite? I hope we can stop it. So now you don't want to dance, but you're looking right through you. Oh, and the clothes that you wear, we don't need to stand."`
- chunk @64.9s len 58.7s chars 345: `"Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing. How much pain that is—it's aching so exquisite. I hope we can stop in time. Now you don't wanna dance, so look around for you. Oh, and the clothes that you wear, we don't need to stare. Oh, but the people you know, they say what they want to."`
- chunk @123.6s len 59.8s chars 56: `"Oh, who doesn't know what it is? We don't really care."`

### asr Ridgway_-_Fire_Inside chunk60
- chunk @0.0s len 60.2s chars 247: `"I got a lot on my mind and all of the time I'm trying to do right. I may have lost a life but I'm keeping it tight. Never give up the fight. No, when my life is on edge, when my life is on edge, got to keep it on in check. I keep it on in check."`
- chunk @60.2s len 60.9s chars 412: `"Even in the darkest days, got a trail to blaze, gonna stick to my ways. I used to be caught in a maze where life was a maze until I saw the sun's rays. When your life is a race, you got to take the first step. Whoa, oh, oh, oh, oh, headlong through the waves now. Whoa, oh, oh, oh, oh, gonna take me to that place. Whoa, oh, oh, oh, oh, find that fire inside. Whoa, oh, oh, oh, oh, it's a fate that you decide."`
- chunk @121.0s len 60.7s chars 474: `"When I feel like I'm losing control, gotta reach within my soul. And if you're ever feeling low, yeah, you gotta take the first step. And girl, yeah, take that first step to the right. Got to find what's inside before we run out of time, run out of time, run out of time. Whoa, oh, oh, oh, oh, ride on through the waves now. Whoa, oh, oh, oh, oh, gonna take me to that place. Whoa, oh, oh, oh, oh, find that fire inside. Whoa, oh, oh, oh, oh, it's a faith that you decide."`
- chunk @181.7s len 55.5s chars 18: `"That you desire."`
- chunk @237.2s len 46.8s chars 213: `"Oh, I'm paddling on, I'm paddling strong. Oh, find the fire, find the fire. Oh, I'm paddling on, I'm paddling strong. Oh, find the fire, find the fire. Find the fire. Find the fire. Find the fire. Find the fire."`

### asr Ridgway_-_Fire_Inside.gated chunk60
- chunk @0.0s len 63.3s chars 238: `"I got a lot on my mind and all of the time be trying to do right. I may have lost a life but I'm keeping it tight. Never give up the fight. No, when my life is on edge, when my life is on edge, got to keep it on edge. I keep it on edge."`
- chunk @63.3s len 57.7s chars 426: `"Even in the darkest days, got a trail to blaze, gonna stick to my ways. I used to be caught in a maze where life was a maze until I saw the sun's rays. When your life is a race, you got to take the first step. Whoa, whoa, whoa, whoa, whoa, headlong through the waves now. Whoa, whoa, whoa, whoa, gonna take me to that place. Whoa, whoa, whoa, whoa, find that fire inside. Whoa, whoa, whoa, whoa, it's a fate that you decide."`
- chunk @121.0s len 60.7s chars 484: `"When I feel like I'm losing control, gotta reach within myself. And if you're ever feeling low, yeah, you gotta take the first step. And girl, yeah, take that first step to the right. Got to find what's inside before we run out of time, run out of time, run out of time. Whoa, whoa, whoa, whoa, ride along through the waves now. Whoa, whoa, whoa, whoa, gonna take me to that place. Whoa, whoa, whoa, whoa, find that fire inside. Whoa, whoa, whoa, whoa, it's a faith that you decide."`
- chunk @181.7s len 55.5s chars 19: `"That you deserve."`
- chunk @237.2s len 46.8s chars 183: `"Oh, I'm paddling on, I'm paddling strong. Oh, find the fire, find the fire. Oh, I'm paddling on, I'm paddling strong. Oh, find the fire, find the fire. Find the fire. Find the fire."`

### asr Songwriterz_-_Back_In_Time chunk60
- chunk @0.0s len 58.9s chars 444: `"Honey, I told you something. Sorry, I didn't hear. Maybe there is something. Yeah, yeah. Stuck in your ear. Why is it every time you say you do, you don't? Maybe I just thought that you were talking on the phone. Honey, you look lovely tonight. Sorry, wasting time. Maybe they say you're lucky now. But trying ain't a crime. Why is it every time I like to do, you don't? Maybe you could try a little romance and a comb. Let's go back in time."`
- chunk @58.9s len 63.8s chars 427: `"Way back when we were la la la la la la la la It's Merry Lads and they live straight to be la la la la la la la la la la la la la la Honey getting older, getting used to twenty nine, and maybe things are colder, but honey still you're mine. Guess it's easy to forget the more that we're apart. Could it be the magic keeping love alive? Let's go back in time, way back when we were la la la la la la la la Back when you and I."`
- chunk @122.7s len 56.2s chars 219: `"Still had time to be la la la la la la la la la la la la la la la la. Let's go back in time. Way back when we were la la la la la la la la la la. Back when you and I still had time to be la la la la la. Let's go back."`
- chunk @178.9s len 30.1s chars 146: `"Back in time, way back when we were la la la la la la la. Now it's married life, still we have to try to be la la la la la la la la la la la la."`

### asr The.madpix.project_-_One_Way_Street chunk60
- chunk @0.0s len 64.9s chars 385: `"Tears are like diamonds in my eyes. Light me up, now you're out of sight. It's enough. It's too late to break this silence. In a rose-colored view of us, I got lost. Could I realize all your lies would be played tonight to stab me inside? Who will save you from this dark? Who will fix your selfish heart? A one-way street. That's how you live. Why do you always take and never give?"`
- chunk @64.9s len 59.8s chars 477: `"Wide awake, yeah I've crossed the line. I'm coming home, I'm running back to real life, to the start where I could breathe and freely, baby. Can't you see we run out of time? Chase happiness while you get what you need. There's nothing left of us but bleeding blades and knives tonight. You'll know how it feels. The one way street, that's how you leave. Why do you always take and never give? I walk away to help you see our love is rolling down so easily. A one way street."`
- chunk @124.7s len 46.3s chars 74: `"A one way street. You never give. I walk away so easily. One way street."`

### asr The_Rinn_-_Voices__2017_Version_ chunk60
- chunk @0.0s len 62.5s chars 66: `"The sun is fading under blood red sky. The reign of day is over."`
- chunk @62.5s len 57.9s chars 555: `"Nights soon will break, but we they wait in the eerie glow of moonlight for stars beyond our sight. While the sky forever glows in the rising light, they shine with mystery, lost in many shadows, lost in whispering. They are moonlight. It's bright. You're waking in the morning, can't understand your feelings, and when you get these thoughts inside your mind, the voice is calling for the night to rise at your side. While the sky forever glows in the rising light, they shine with mystery, lost in many shadows, lost in whispering. They are moonlight."`
- chunk @120.4s len 59.6s chars 233: `"We lost, we made the shadows of our time whispering their old lies. So hear the voice, sharing the hidden, give the giving to you. Hear the voice, sharing the memories, secrets, secrets from past times. It's gone forever, long ago."`
- chunk @180.0s len 51.2s chars 287: `"The shine will miss. Lost in shadows of our time, whispering in the moonlight. So hear the voice, sharing the guiding, keeping, keeping to you. Hear the voice, sharing the memories, secrets, secrets from us. Hear the voice, sharing the guiding, keeping, keeping to you. Hear the voice."`

