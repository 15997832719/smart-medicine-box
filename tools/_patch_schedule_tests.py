from pathlib import Path
p = Path(r'D:\smart-medicine-box\backend\tests\test_voice_intents.py')
s = p.read_text(encoding='utf-8')
s = s.replace('from datetime import time\n', 'from datetime import date, time, timedelta\n')
old = "    def test_stock_reply_is_chinese(self) -> None:\n"
new = """    def test_future_specific_date_is_not_in_today_summary(self) -> None:
        future_medicine = Medicine(
            name='未来药',
            owner_id=1,
            stock_count=5,
            low_stock_threshold=1,
        )
        self.session.add(future_medicine)
        self.session.commit()
        self.session.refresh(future_medicine)
        future_reminder = Reminder(
            owner_id=1,
            medicine_id=future_medicine.id or 0,
            title='明天用药',
            dose='1片',
            remind_time=time(8, 0),
            schedule_date=date.today() + timedelta(days=1),
            enabled=True,
        )
        self.session.add(future_reminder)
        self.session.commit()

        result = _voice_intent(VoiceIntentRequest(text='今天吃什么药'), self.user, self.session)
        self.assertTrue(result['success'])
        self.assertNotIn('未来药', result['reply'])
        self.assertIn('阿司匹林', result['reply'])

    def test_stock_reply_is_chinese(self) -> None:
"""
if s.count(old)!=1: raise SystemExit(f'test anchor count={s.count(old)}')
s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')
print('schedule date test added')
