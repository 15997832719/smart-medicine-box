from app.voice_intents import shi_bie_yu_yin_yi_tu
questions=["我的药库存还剩多少","药品还剩多少","库存还有几盒","存货余量是多少","阿司匹林还剩多少片","药快吃完了吗","药够不够","还有多少药片"]
for q in questions: print(repr(q), shi_bie_yu_yin_yi_tu(q))
