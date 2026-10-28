import unittest

from app.instruction_parser import parse_instruction_text


class InstructionParserTests(unittest.TestCase):
    def test_extracts_required_sections(self) -> None:
        text = '''
【药品名称】阿司匹林肠溶片
【商品名称】拜阿司匹灵
【规格】100mg
【生产企业】示例制药有限公司
【批准文号】国药准字H00000000
【用法用量】口服，一次1片，一日1次。
【禁忌】对本品过敏者禁用。
【注意事项】胃溃疡患者慎用。
【不良反应】可能出现胃部不适。
【药物相互作用】与其他抗凝药合用需咨询医生。
'''
        result = parse_instruction_text(text)
        self.assertEqual(result['name'], '阿司匹林肠溶片')
        self.assertEqual(result['aliases'], '拜阿司匹灵')
        self.assertEqual(result['specification'], '100mg')
        self.assertIn('一次1片', result['dosage'])
        self.assertIn('过敏者禁用', result['contraindications'])
        self.assertIn('胃溃疡', result['precautions'])
        self.assertIn('抗凝药', result['interactions'])
        self.assertIn('阿司匹林肠溶片', result['raw_excerpt'])

    def test_plain_text_with_colon_headings(self) -> None:
        result = parse_instruction_text('药品名称: 测试药\n用法用量: 每日一次\n注意事项: 遵医嘱')
        self.assertEqual(result['name'], '测试药')
        self.assertEqual(result['dosage'], '每日一次')
        self.assertEqual(result['precautions'], '遵医嘱')


if __name__ == '__main__':
    unittest.main()
