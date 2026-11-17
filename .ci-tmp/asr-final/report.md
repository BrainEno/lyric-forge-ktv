# Qwen3-ASR loop experiment

| model | song | config | exit | s | max_new_tokens | chunks | lines (ref) | words (ref) | WER | words outside sung lines | longest block loop | longest chunk raw chars |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0.6B | Avercage_-_Embers | final_patched | 0 | 211 | 368 | 8 | 30 (42) | 140 (189) | 0.73 | 6 | - | 173 |
| 0.6B | Avercage_-_Embers.gated | final_patched | 0 | 213 | 368 | 9 | 31 (42) | 136 (189) | 0.72 | 2 | 3x1@213s | 169 |
| 0.6B | Kinematic_-_Peyote | final_patched | 0 | 166 | 368 | 6 | 27 (14) | 148 (147) | 0.23 | 18 | - | 227 |
| 0.6B | Kinematic_-_Peyote.gated | final_patched | 0 | 186 | 368 | 7 | 29 (14) | 148 (147) | 0.28 | 7 | - | 194 |
| 0.6B | Ridgway_-_Fire_Inside | final_patched | 0 | 327 | 368 | 10 | 42 (50) | 257 (304) | 0.35 | 17 | - | 332 |
| 0.6B | Ridgway_-_Fire_Inside.gated | final_patched | 0 | 281 | 368 | 10 | 37 (50) | 254 (304) | 0.37 | 4 | - | 286 |
| 0.6B | Songwriterz_-_Back_In_Time | final_patched | 0 | 236 | 368 | 7 | 36 (46) | 297 (238) | 0.54 | 2 | - | 287 |
| 0.6B | The.madpix.project_-_One_Way_Street | final_patched | 0 | 196 | 368 | 6 | 24 (30) | 181 (183) | 0.25 | 4 | - | 345 |
| 0.6B | The_Rinn_-_Voices__2017_Version_ | final_patched | 0 | 234 | 368 | 8 | 31 (46) | 199 (203) | 0.52 | 12 | - | 259 |
| 1.7B | Avercage_-_Embers | final_patched | 0 | 422 | 368 | 8 | 32 (42) | 137 (189) | 0.64 | 4 | - | 737 |
| 1.7B | Avercage_-_Embers.gated | final_patched | 0 | 428 | 368 | 9 | 32 (42) | 123 (189) | 0.70 | 5 | - | 1289 |
| 1.7B | Kinematic_-_Peyote | final_patched | 0 | 312 | 368 | 6 | 27 (14) | 150 (147) | 0.22 | 15 | - | 737 |
| 1.7B | Kinematic_-_Peyote.gated | final_patched | 0 | 399 | 368 | 7 | 32 (14) | 146 (147) | 0.22 | 8 | - | 737 |
| 1.7B | Ridgway_-_Fire_Inside | final_patched | 0 | 452 | 368 | 10 | 45 (50) | 254 (304) | 0.33 | 20 | - | 737 |
| 1.7B | Ridgway_-_Fire_Inside.gated | final_patched | 0 | 475 | 368 | 10 | 44 (50) | 264 (304) | 0.29 | 5 | - | 737 |
| 1.7B | Songwriterz_-_Back_In_Time | final_patched | 0 | 200 | 368 | 7 | 40 (46) | 276 (238) | 0.43 | 2 | - | 289 |
| 1.7B | The.madpix.project_-_One_Way_Street | final_patched | 0 | 179 | 368 | 6 | 27 (30) | 183 (183) | 0.19 | 4 | - | 352 |
| 1.7B | The_Rinn_-_Voices__2017_Version_ | final_patched | 0 | 408 | 368 | 8 | 29 (46) | 192 (203) | 0.50 | 12 | - | 737 |

## Averages

| model | config | runs | mean WER | words outside sung lines | lines / ref lines |
|---|---|---|---|---|---|
| 0.6B | final_patched | 9 | 0.444 | 72 | 287/334 |
| 1.7B | final_patched | 9 | 0.389 | 75 | 308/334 |

## Raw chunk outputs (first 600 chars)

### 0.6B Avercage_-_Embers final_patched
- chunk @0.0s len 31.3s chars 6: `"The."`
- chunk @31.3s len 33.9s chars 173: `"You can't just continue starting fights where we don't know. When you leave, carry the torch. There will be no where we are. We don't know for the moment when we will die."`
- chunk @65.2s len 29.6s chars 140: `"Fade into the dust of a long day. One day long, but can't forever, can't forever. Don't close your eyes, but can't forever, can't forever."`
- chunk @94.8s len 34.3s chars 129: `"Just fit for the joy of the gods. Hey, you are the perfect man. Nothing in the dark of the night. Nothing. One day you'll come."`
- chunk @129.0s len 27.4s chars 78: `"Forever, oh come forever, close your eyes. Oh come forever, oh come forever."`
- chunk @156.4s len 32.8s chars 26: `"And you are the promise."`
- chunk @189.2s len 25.2s chars 132: `"Wonderful, oh God, forever, oh God, forever, don't close your eyes, oh God, forever, oh God, forever, don't stop, oh God, forever."`
- chunk @214.4s len 28.1s chars 85: `"Never, never stop. I've seen the end. The flame is burning, but living never stops."`

### 0.6B Avercage_-_Embers.gated final_patched
- chunk @0.0s len 31.3s chars 6: `"The."`
- chunk @31.3s len 33.9s chars 169: `"You can't just continue starting fights where we don't know. We really can't reach Juliet. There will be no where we are. We don't know for the moment when we are not."`
- chunk @65.2s len 29.6s chars 140: `"Fade into the dust of a long day. One day long, but can't forever, can't forever. Don't close your eyes, but can't forever, can't forever."`
- chunk @94.8s len 34.3s chars 146: `"Just keep on going, don't stop. Don't stop. Hey, you are the one who burns my heart. Nothing in the dark can make me lonely. One day, I'll come."`
- chunk @129.0s len 27.3s chars 81: `"Forever, oh God forever, don't close your eyes. Oh God forever, oh God forever."`
- chunk @156.3s len 25.2s chars 10: `"Promise."`
- chunk @181.5s len 28.0s chars 86: `"One day you'll go forever, go forever. Don't lose your eyes, go forever, go forever."`
- chunk @209.5s len 31.6s chars 106: `"Never more, never, never, never. Never, never, once in the end, the flame is rendered, but living never."`
- chunk @241.1s len 1.5s chars 7: `"Okay."`

### 0.6B Kinematic_-_Peyote final_patched
- chunk @0.0s len 34.7s chars 118: `"I'm asleep at the wheel, and there's a car in the highway. Yet we tear through the night like a beat your microwave."`
- chunk @34.7s len 33.2s chars 181: `"How much better is it? Aching so exquisite. I hope we can stop it. Now you don't want to dance. You're looking like you. Oh, and the clothes that you wear. We don't need to stare."`
- chunk @68.0s len 33.2s chars 179: `"Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing. How much fire that is? It's aching so exquisite. I hope we can stop in time."`
- chunk @101.2s len 33.1s chars 227: `"Now you don't want to turn, cause we look around for you. Oh, and the clothes that you wear, we don't need to stare. Oh, but the people you know, they say what they want to. Oh, cause the truth of it is, we don't really care."`
- chunk @134.3s len 25.5s chars 5: `"Oh."`
- chunk @159.8s len 23.5s chars 30: `"That's quite enough of that."`

### 0.6B Kinematic_-_Peyote.gated final_patched
- chunk @0.0s len 29.2s chars 60: `"I'm asleep on the wheel, and there's a car in the highway."`
- chunk @29.2s len 29.9s chars 194: `"Yet we tap through the night like a beat of your microwave. How much better is it? Aching so exquisite. I hope we can stop inside. Now you don't want to dance. So look at life through you. Oh."`
- chunk @59.0s len 28.1s chars 153: `"And the clothes that you wear with only two steps. Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing."`
- chunk @87.2s len 28.9s chars 188: `"How much better is it? Aching so exquisite. I hope we can stop in time. Now you don't want to dance, cause look around for you. Oh, and the clothes that you wear, we don't need to stare."`
- chunk @116.0s len 25.7s chars 110: `"Oh, but the people you know—they say what they want to. Oh, because the truth of it is we don't really care."`
- chunk @141.7s len 34.7s chars 8: `"Music."`
- chunk @176.4s len 7.0s chars 32: `"That's quite a matter of that."`

### 0.6B Ridgway_-_Fire_Inside final_patched
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

### 0.6B Ridgway_-_Fire_Inside.gated final_patched
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

### 0.6B Songwriterz_-_Back_In_Time final_patched
- chunk @0.0s len 26.3s chars 164: `"Honey, I told you something. Sorry, I didn't hear. Maybe there is something. Yeah, yeah, yeah, stuck in your ear. Why you say every time you say you do you don't."`
- chunk @26.3s len 32.6s chars 287: `"Maybe I just thought that you were talking on the phone. Honey, you look lovely tonight. Sorry, you're wasting time. Maybe this is your lucky night. Well, crying ain't a crime. Why is it every time I like to do you don't? Maybe you could try a little Romanesque. Let's go back in time."`
- chunk @58.9s len 31.1s chars 205: `"Way that way we were, la la la la la la la la la. It's memory light and the daily strife to be, la la la la la la la la la. La la la la la la la la la la la la la la. Honey, get no doubt. Yeah, years to."`
- chunk @90.1s len 32.6s chars 261: `"Twenty nine, and maybe things are colder, but only you still your mind. Guess it's easy to forget the more the man away. Could it be that love magic keeping love alive? Let's go back in time, way back when we were la la la la la la la la. Back when you and I."`
- chunk @122.7s len 34.7s chars 71: `"Still had time to be la la la la la la la la la la la la la la la la."`
- chunk @157.4s len 30.6s chars 216: `"Let's go back in time, way back when. We were la la la la la la la la la. Back when you and I still had time to feel la la la la la la la la. Let's go back in time, way back when we were la la la la la la la la la."`
- chunk @187.9s len 21.1s chars 96: `"Now it's Mary life for you. We have to try to be la la la la la la la la la la la la la la la."`

### 0.6B The.madpix.project_-_One_Way_Street final_patched
- chunk @0.0s len 34.0s chars 173: `"Ears like diamonds in my eyes, like me so now you're out of sight. It's enough. It's too late to break this silence. In a rose-colored view of us, I got lost. Could I read"`
- chunk @34.0s len 30.9s chars 216: `"All your lies, all your lies would be blades and knives. Just tap me inside. I will save you from the dark. I will fix your selfish heart. A one-way street. It's how you live. Why do you always take and never give?"`
- chunk @64.9s len 27.9s chars 129: `"Wide awake, yeah, I've crossed the line. I'm coming home, I'm running back to real life, to the start where I could breathe in."`
- chunk @92.8s len 31.9s chars 345: `"Freelee baby, can you see we run out of time chasing happiness while you get what you need? There's nothing left of us but bleeding blades of knives tonight. You'll know how it feels in one way street. That's how you leave. Why do you always take a never leave? I walk away to help you see our love is rolling down so easily in one way street."`
- chunk @124.7s len 33.4s chars 20: `"At one-way street."`
- chunk @158.1s len 12.9s chars 40: `"You never give. I walk away so easily."`

### 0.6B The_Rinn_-_Voices__2017_Version_ final_patched
- chunk @0.0s len 30.4s chars 6: `"The."`
- chunk @30.4s len 32.1s chars 66: `"The sun is fading under blood red sky. The reign of day is over."`
- chunk @62.5s len 28.5s chars 250: `"Night, so we'll break free. They wake in the eerie glow of moonlight. Forgotten shadows beyond our sight. World is gone forever. All that's gone was in the eyes that shine. We miss we lost we made each other's last night. Whispering they will rise."`
- chunk @91.0s len 29.4s chars 259: `"It's bright. You're waking in the morning. Can't understand your feelings. And when you get these thoughts inside your mind, the voice calling for the night to rise at your side. Oh, love, the sun forever morning. Lost in the night, the light shine with me."`
- chunk @120.4s len 28.4s chars 198: `"We lost, we made shadows. Upside, whisper you there would lie. Don't hear the voice sharing the yearning, keep it deep into you. Hear the voice sharing the memories, sacred secrets from past time."`
- chunk @148.8s len 31.2s chars 41: `"World gets gone forever. A lot of gold."`
- chunk @180.0s len 27.6s chars 214: `"The shine we missed, we lost, we made in shadows of our sight. Whispering the old lies. So hear the voice sharing the gunning, keep them keeping to you. Hear the voice sharing the memories, secrets, secrets from."`
- chunk @207.6s len 23.6s chars 74: `"Hear the voice sharing the agony, keeping it within you. Hear the voice."`

### 1.7B Avercage_-_Embers final_patched
- chunk @0.0s len 31.3s chars 737: `"Oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh,`
- chunk @31.3s len 33.9s chars 166: `"The thunder's continuing started, but we all know we're gonna carry it to the end. Never whispered, never be afraid. We all know when the moment's right, we ignite."`
- chunk @65.2s len 29.6s chars 97: `"One day it'll be gone forever, gone forever. Don't close your eyes, gone forever, gone forever."`
- chunk @94.8s len 34.3s chars 202: `"Just feel the poison, draw your blood and go. Hey, hey, what you want? Live for love, live on the edge. No need to be in doubt of running, running. It's only love, only love. One day it all will come."`
- chunk @129.0s len 27.4s chars 80: `"Gone forever, gone forever. Don't close your eyes. Gone forever, gone forever."`
- chunk @156.4s len 32.8s chars 16: `"And I promise."`
- chunk @189.2s len 25.2s chars 115: `"One day, oh, oh, forever, oh, forever, don't close your eyes, oh, oh, forever, oh, forever, let's make our plans."`
- chunk @214.4s len 28.1s chars 79: `"Never, never, once in the end, the plan was rendered. But living never stops."`

### 1.7B Avercage_-_Embers.gated final_patched
- chunk @0.0s len 31.3s chars 17: `"I'm not a hero."`
- chunk @31.3s len 33.9s chars 160: `"The thunder's continuing started, but we all know we'll carry it to the end. Never whispered, never be afraid. We all know the moment when we realize love is."`
- chunk @65.2s len 29.6s chars 97: `"One day it'll be gone forever, gone forever. Don't close your eyes, gone forever, gone forever."`
- chunk @94.8s len 34.3s chars 165: `"Just feel the power. So you burn and glow. Hey, you are the one. Live on the top of the sun. No need to doubt or blame. No need to blame. One day it all will come."`
- chunk @129.0s len 27.3s chars 80: `"Gone forever, gone forever. Don't close your eyes. Gone forever, gone forever."`
- chunk @156.3s len 25.2s chars 16: `"And I promise."`
- chunk @181.5s len 28.0s chars 112: `"One day, oh, oh, girl, forever, oh, girl, forever. Don't lose your mind, oh, girl, forever, oh, girl, forever."`
- chunk @209.5s len 31.6s chars 1289: `"Never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, never, neve`
- chunk @241.1s len 1.5s chars 7: `"Okay."`

### 1.7B Kinematic_-_Peyote final_patched
- chunk @0.0s len 34.7s chars 114: `"I'm asleep at the wheel and there's a car in the highway. Yet we tear through the night like a bee after nectar."`
- chunk @34.7s len 33.2s chars 203: `"How much pain that is it aching so exquisite? I hope we can't stop inside. Now you don't wanna dance, 'cause you're looking right through you. Oh, and the clothes that you wear, we don't need to stand."`
- chunk @68.0s len 33.2s chars 179: `"Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing. How much pain there is—it's aching so exquisite. I hope we can stop in time."`
- chunk @101.2s len 33.1s chars 236: `"Now you don't wanna dance 'cause we're looking right through you. Oh, and the clothes that you wear, we don't mean to stare. Oh, but the people you know, they say what they want to. Oh, 'cause the truth of it is, we don't really care."`
- chunk @134.3s len 25.5s chars 737: `"Oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh,`
- chunk @159.8s len 23.5s chars 34: `"And that's quite enough of that."`

### 1.7B Kinematic_-_Peyote.gated final_patched
- chunk @0.0s len 29.2s chars 59: `"I'm asleep at the wheel and there's a car in the highway."`
- chunk @29.2s len 29.9s chars 204: `"Yet we tear through the night like a bee after migraine. How much pain that is—it's aching so exquisite. I hope we can stop inside. Now you don't wanna dance, 'cause we're looking right through you. Oh."`
- chunk @59.0s len 28.1s chars 157: `"And the clothes that you wear, we don't mean to stare. Now the sky is on fire and the desert is freezing. Wonder how I'm alive when I'm not even breathing."`
- chunk @87.2s len 28.9s chars 185: `"How much further is it aching so exquisite? I hope we can stop in time. Now you don't wanna dance 'cause you look horrendous. Oh, and the clothes that you wear we don't need to stare."`
- chunk @116.0s len 25.7s chars 105: `"But the people you know they say what they want to. Oh, 'cause the truth of it is we don't really care."`
- chunk @141.7s len 34.7s chars 737: `"Oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh,`
- chunk @176.4s len 7.0s chars 34: `"And that's quite enough of that."`

### 1.7B Ridgway_-_Fire_Inside final_patched
- chunk @0.0s len 25.5s chars 737: `"Oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh,`
- chunk @25.5s len 34.7s chars 249: `"I got a lot on my mind, darling. All of the time, be trying to do right. I've made a lot of life, but I'm keeping it tight. Never give up the fight, no. When my life is on edge, when my life is on edge, got to keep it on check. I keep it on check."`
- chunk @60.2s len 34.6s chars 273: `"Even in the darkest days, got a trail to blaze, gonna stick to my ways. I used to be caught in a maze where life was a maze until I saw the sun's rays. When your life is a race, you got to take the first step. Whoa, whoa, whoa, whoa, whoa! Headlong through the waves now."`
- chunk @94.8s len 34.7s chars 100: `"Whoa, gonna take me to that place. Whoa, find that fire inside. Whoa, it's a fate that you decide."`
- chunk @129.5s len 34.3s chars 308: `"When I feel like I'm losing control, gotta reach within my soul. And if you're ever feeling low, yeah, you gotta take the first step. And girl, yeah, take that first step to the right. Got to find what's inside before we run out of time. Run out of time. Run out of time. Whoa, along through the waves now."`
- chunk @163.8s len 25.0s chars 117: `"Whoa, gonna take me to that place. Whoa, find that fire inside. Whoa, it's a fate that you decide. That you decide."`
- chunk @188.8s len 34.6s chars 5: `"Oh."`
- chunk @223.4s len 28.4s chars 104: `"Whoa, I'm paddling on, I'm paddling strong. Whoa, find the fire, find the fire. Whoa, I'm paddling on."`
- chunk @251.8s len 31.6s chars 91: `"I'm paralyzed. Find the fire. Find the fire. Find the fire. Find the fire. Find the fire."`
- chunk @283.4s len 0.5s chars 7: `"Yeah."`

### 1.7B Ridgway_-_Fire_Inside.gated final_patched
- chunk @0.0s len 25.4s chars 737: `"Oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh,`
- chunk @25.4s len 34.7s chars 242: `"I got a lot on my mind and all of the time I'm trying to do right. I've made a loss of life, but I'm keeping it tight. Never give the final when my life is on edge. When my life is on edge, got to keep it on in check. I keep it on in check."`
- chunk @60.2s len 34.6s chars 272: `"Even in the darkest days, got a trail to blaze, gonna stick to my ways. I used to be caught in a maze where life was a maze until I saw the sun's rays. When your life is a rig, you got to take the first step. Whoa, whoa, whoa, whoa, whoa. Headlong through the waves now."`
- chunk @94.8s len 26.2s chars 100: `"Whoa, gonna take me to that place. Whoa, find that fire inside. Whoa, it's a fate that you decide."`
- chunk @121.0s len 32.9s chars 210: `"When I feel like I'm losing control, gotta reach within my soul. And if you're ever feeling low, yeah, you gotta take the first step and go, yeah. Take that first step to the right. Got to find what's inside."`
- chunk @153.9s len 33.7s chars 281: `"Before we run out of time, run out of time, run out of time. Whoa, oh, oh, oh, oh. That long through the waves now. Whoa, oh, oh, oh, oh. Gonna take me to that place. Whoa, oh, oh, oh, oh. Find that fire inside. Whoa, oh, oh, oh, oh. It's a fate that you decide. That you decide."`
- chunk @187.6s len 32.8s chars 5: `"Oh."`
- chunk @220.4s len 31.4s chars 82: `"I'm paddling on, I'm paddling strong. Find the fire, find the fire. Paddling on."`
- chunk @251.8s len 30.8s chars 76: `"I'm paralyzed. Find the fire. Find the fire. Find the fire. Find the fire."`
- chunk @282.6s len 1.4s chars 7: `"Okay."`

### 1.7B Songwriterz_-_Back_In_Time final_patched
- chunk @0.0s len 26.3s chars 145: `"Honey, I told you something. Sorry, I didn't hear. Maybe there was something stuck in your ear. Why is it every time you say you do, you don't?"`
- chunk @26.3s len 32.6s chars 289: `"Maybe I just thought that you were talking on the phone. Honey, you look lovely tonight. Sorry, wasting time. Maybe this ain't your lucky night. Well, trying ain't a crime. Why is it every time I like to do, you don't? Maybe you could try a little romance at home. Let's go back in time."`
- chunk @58.9s len 31.1s chars 181: `"Way back when we were la la la la la la la, now it's married life and the daily strife. You be la la la la la la la la la la la la la la la. Honey, getting older, getting used to."`
- chunk @90.1s len 32.6s chars 258: `"29, and maybe things are colder. But honey, you still are mine. Guess it's easy to forget the more the man a wine. Could it be the love, love, magic keeping love alive? Let's go back in time, way back when we were la la la la la la la. Back when you and I."`
- chunk @122.7s len 34.7s chars 78: `"Still held tight, you've been la la la la la, la la la la la la la la la la."`
- chunk @157.4s len 30.6s chars 192: `"Let's go back in time, way back when we were la la la la la la la. Back when you and I still had time to be la la la la la. Let's go back in time, way back when we were la la la la la la la."`
- chunk @187.9s len 21.1s chars 98: `"Now it's very light, still we have to try to be. La la la la la, la la la la la, la la la la la."`

### 1.7B The.madpix.project_-_One_Way_Street final_patched
- chunk @0.0s len 34.0s chars 181: `"Tears are like diamonds in my eyes. Light me up. Now you're out of sight. It's enough. It's too late to break the silence. In a rose-colored view of us, I got lost. Could I reach?"`
- chunk @34.0s len 30.9s chars 224: `"All your lies, all your lies would be blades and knives. Just have me inside. Who will save you from this dark? Who will fix your selfish heart? A one-way street. That's how you live. Why do you always take and never give?"`
- chunk @64.9s len 27.9s chars 129: `"Wide awake, yeah, I've crossed the line. I'm coming home. I'm running back to real life, to the start where I could breathe in."`
- chunk @92.8s len 31.9s chars 352: `"Freely, baby, can't you see we run out of time chasing happiness while you get what you need. There's nothing left of us but bleeding blades and knives tonight. You'll know how it feels. A one-way street. That's how you leave. Why do you always take and never give? I'll walk away to help you see our love is falling down so easily. A one-way street."`
- chunk @124.7s len 33.4s chars 19: `"A one-way street."`
- chunk @158.1s len 12.9s chars 56: `"You never give. I walk away so easily. One way street."`

### 1.7B The_Rinn_-_Voices__2017_Version_ final_patched
- chunk @0.0s len 30.4s chars 737: `"Oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh, oh,`
- chunk @30.4s len 32.1s chars 66: `"The sun is fading under blood red sky. The reign of day is over."`
- chunk @62.5s len 28.5s chars 232: `"Night soon will break. Free, they wait in the glow of moonlight for guiding stars beyond our sight. Will the sky forever honor those in the night? They shine with mystery, lost within shadows of a star, whispering they will light."`
- chunk @91.0s len 29.4s chars 247: `"Surprise! You're waking in the morning. Can't understand your feelings. And where do you get these thoughts inside your mind? The voice is calling for the night to rise at your side. Oh, the sky forever on and on, crossing the horizon with mist."`
- chunk @120.4s len 28.4s chars 198: `"We lost, we made the shadows of our time whispering the old lie. So hear the voice, sharing the hidden, keep the gift into you. Hear the voice, sharing the memories, sacred secrets from lost time."`
- chunk @148.8s len 31.2s chars 39: `"A world that's gone forever long ago."`
- chunk @180.0s len 27.6s chars 209: `"They shine. We're lost. We're made in shadows of our time. Whispering their wills. So hear the voice, sharing the memories, keeping, keeping to you. Hear the voice, sharing the memories, sacred secrets from."`
- chunk @207.6s len 23.6s chars 73: `"Hear the voice tearing the sky. Deep and deep into you. Hear the voice."`

