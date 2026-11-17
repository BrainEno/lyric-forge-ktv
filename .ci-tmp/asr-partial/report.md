# Qwen3-ASR loop experiment

| model | song | config | exit | s | max_new_tokens | chunks | lines (ref) | words (ref) | WER | words outside sung lines | longest block loop | longest chunk raw chars |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0.6B | Avercage_-_Embers | chunk30 | 0 | 152 | 368 | 8 | 24 (42) | 105 (189) | 0.86 | 8 | 2x1@0s | 182 |
| 0.6B | Avercage_-_Embers | chunk30_noctx | 0 | 176 | 368 | 8 | 30 (42) | 140 (189) | 0.73 | 6 | - | 173 |
| 0.6B | Avercage_-_Embers.gated | chunk30 | 0 | 359 | 368 | 9 | 27 (42) | 100 (189) | 0.85 | 14 | - | 939 |
| 0.6B | Avercage_-_Embers.gated | chunk30_noctx | 0 | 176 | 368 | 9 | 31 (42) | 136 (189) | 0.72 | 2 | 3x1@213s | 169 |
| 0.6B | Kinematic_-_Peyote | chunk30 | 0 | 125 | 368 | 6 | 27 (14) | 146 (147) | 0.24 | 14 | - | 228 |
| 0.6B | Kinematic_-_Peyote | chunk30_noctx | 0 | 137 | 368 | 6 | 27 (14) | 148 (147) | 0.23 | 18 | - | 227 |
| 0.6B | Kinematic_-_Peyote.gated | chunk30 | 0 | 134 | 368 | 7 | 30 (14) | 149 (147) | 0.29 | 8 | - | 190 |
| 0.6B | Kinematic_-_Peyote.gated | chunk30_noctx | 0 | 153 | 368 | 7 | 29 (14) | 148 (147) | 0.28 | 7 | - | 194 |
| 0.6B | Ridgway_-_Fire_Inside | chunk30 | 0 | 229 | 368 | 10 | 45 (50) | 273 (304) | 0.35 | 29 | - | 332 |
| 0.6B | Ridgway_-_Fire_Inside | chunk30_noctx | 1 | 265 | 368 | 10 | 0 (50) | 0 (304) | - | 0 | - | 332 |
| 0.6B | Ridgway_-_Fire_Inside.gated | chunk30 | 0 | 204 | 368 | 10 | 39 (50) | 264 (304) | 0.37 | 14 | - | 286 |
| 0.6B | Ridgway_-_Fire_Inside.gated | chunk30_noctx | 0 | 231 | 368 | 10 | 37 (50) | 254 (304) | 0.37 | 4 | - | 286 |
| 0.6B | Songwriterz_-_Back_In_Time | chunk30 | 0 | 170 | 368 | 7 | 37 (46) | 296 (238) | 0.54 | 2 | - | 287 |
| 0.6B | Songwriterz_-_Back_In_Time | chunk30_noctx | 0 | 197 | 368 | 7 | 36 (46) | 297 (238) | 0.54 | 2 | - | 287 |
| 0.6B | The.madpix.project_-_One_Way_Street | chunk30 | 0 | 139 | 368 | 6 | 25 (30) | 189 (183) | 0.22 | 5 | - | 346 |
| 0.6B | The.madpix.project_-_One_Way_Street | chunk30_noctx | 0 | 161 | 368 | 6 | 24 (30) | 181 (183) | 0.25 | 4 | - | 345 |
| 0.6B | The_Rinn_-_Voices__2017_Version_ | chunk30 | 0 | 163 | 368 | 8 | 29 (46) | 199 (203) | 0.51 | 11 | - | 256 |
| 0.6B | The_Rinn_-_Voices__2017_Version_ | chunk30_noctx | 0 | 193 | 368 | 8 | 31 (46) | 199 (203) | 0.52 | 12 | - | 259 |

## Averages

| model | config | runs | mean WER | words outside sung lines | lines / ref lines |
|---|---|---|---|---|---|
| 0.6B | chunk30 | 9 | 0.469 | 105 | 283/334 |
| 0.6B | chunk30_noctx | 8 | 0.455 | 55 | 245/284 |

## Raw chunk outputs (first 600 chars)

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

