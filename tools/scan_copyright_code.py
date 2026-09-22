from docx import Document
from pathlib import Path
import re, unicodedata
p=Path(r'D:\smart-medicine-box\dist\软著申请材料_最终版\智能药箱家庭用药管理系统_软件代码.docx')
lines=[x.text for x in Document(str(p)).paragraphs if x.text.strip()]
emoji=re.compile('[\U0001F000-\U0001FAFF\u2600-\u27BF\u2B00-\u2BFF\uFE0F\u200D]')
kao=re.compile(r'(?<![A-Za-z0-9_])(?:\^_?\^|>_<|T_T|Q_Q|Orz|orz|:\)|:\(|:D|;P|=\)|=\()(?![A-Za-z0-9_])')
comment_only=[]; inline_hash=[]; double_slash=[]
for i,line in enumerate(lines,1):
    raw=line.split('  ',1)[1] if i and '  ' in line else line
    if re.match(r'^\s*(#|//)', raw): comment_only.append((i,raw))
    if '#' in raw: inline_hash.append((i,raw))
    if '//' in raw and not re.search(r'https?://', raw): double_slash.append((i,raw))
symbols=[]
for i,line in enumerate(lines,1):
    for ch in line:
        if unicodedata.category(ch) in {'So','Sk','Cf'}:
            symbols.append((i,ch,unicodedata.name(ch,'?')))
print('lines',len(lines))
print('emoji_lines',sum(bool(emoji.search(x)) for x in lines))
print('kaomoji_lines',sum(bool(kao.search(x)) for x in lines))
print('comment_only',len(comment_only))
print('lines_with_hash',len(inline_hash))
print('non_url_double_slash',len(double_slash))
print('symbol_chars',len(symbols))
for row in comment_only[:10]: print('comment_only_sample',row)
for row in inline_hash[:10]: print('hash_sample',row)
for row in double_slash[:10]: print('slash_sample',row)
for row in symbols[:20]: print('symbol_sample',row)
