from __future__ import annotations

import hashlib
import io
import re
import tokenize
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_TAB_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt, RGBColor
from docx.enum.style import WD_STYLE_TYPE

ROOT = Path(r'D:\smart-medicine-box')
WORK = ROOT / 'docs' / '软著材料'
SCREENS = WORK / '_screens'
ASSETS = WORK / 'final-assets'
OUT = ROOT / 'dist' / '软著申请材料_最终版'
APP_NAME = '智能药箱家庭用药管理系统'
SHORT_NAME = '智能药箱'
VERSION = 'V1.0'
PACKAGE = 'com.smartmedicine.smart_medicine_box'
APK = ROOT / 'dist' / 'smart-medicine-box-v1.0.0-release-final.apk'
APK_SHA256 = hashlib.sha256(APK.read_bytes()).hexdigest().upper()
MANUAL_TEMPLATE = Path(r'D:\申请材料模板\XXX软件_操作手册.docx')
CODE_TEMPLATE = Path(r'D:\申请材料模板\XXX软件_软件代码.docx')

BODY_FONT = '宋体'
HEAD_FONT = '宋体'
CODE_FONT = '宋体'


@dataclass(frozen=True)
class Figure:
    key: str
    source: str
    title: str
    caption: str
    description: str
    crop_top: int = 72
    crop_bottom: int = 70


FIGURES = [
    Figure('login', '14_login.png', '登录界面', '图 3-1  登录界面', '用户输入手机号和密码登录系统；页面同时提供注册入口。'),
    Figure('register', '15_register.png', '注册界面', '图 3-2  注册账号界面', '用户可选择老人端或家属端角色，填写手机号、昵称、密码和确认密码后完成注册。'),
    Figure('elder_home', '02_elder_home.png', '老人端首页', '图 4-1  老人端首页', '首页集中展示今日服药、药品数量、计划数量、风险告警、下一次提醒和快捷功能入口。'),
    Figure('medicines', '03_medicines.png', '药品管理', '图 4-2  药品管理界面', '支持按全部、正常、临期、过期筛选药品，显示药品用法、有效期及库存状态。'),
    Figure('medicine_detail', '21_medicine_detail.png', '药品详情', '图 4-3  药品详情界面', '详情页展示分类、厂家、用法用量、有效期、库存、提醒数量和注意事项。'),
    Figure('ai_recognize', '06_ai_recognize.png', '拍照识药', '图 4-4  拍照识药界面', '可调用相机拍摄药盒或从相册选择图片，识别结果必须经过人工确认后才能保存。'),
    Figure('instruction_parse', '08_instruction_parse.png', '说明书解析', '图 4-5  说明书解析界面', '粘贴说明书中的用法、禁忌和注意事项，由文本模型提取结构化用药信息。'),
    Figure('schedules', '04_schedules.png', '用药计划', '图 4-6  用药计划列表', '以药品名称为标题展示每天或指定日期、提醒时间和剂量，支持编辑和删除计划。'),
    Figure('add_schedule', '05_add_schedule.png', '添加计划', '图 4-7  添加服药计划', '依次选择药品、设置提醒时间和剂量，保存后生成新的用药提醒。'),
    Figure('edit_schedule', '23_medication_confirm.png', '编辑计划', '图 4-8  编辑服药计划', '编辑页面沿用新增计划流程，可调整药品、提醒时间和剂量并保存修改。'),
    Figure('voice', '09_voice.png', '语音助手', '图 4-9  语音助手界面', '支持语音和文字提问、药名纠错、多轮追问、安全兜底和确认执行。'),
    Figure('alerts', '10_alerts.png', '提醒中心', '图 4-10  提醒中心', '汇总库存不足、临近有效期和漏服风险，并显示今日服药记录。'),
    Figure('profile', '11_profile.png', '老人端个人中心', '图 4-11  老人端个人中心', '展示当前账号角色，提供绑定家属、用药安全声明、音箱接入和退出登录等功能。'),
    Figure('bind_family', '12_bind_family.png', '绑定家属', '图 4-12  生成家属邀请码', '老人端生成有时效性的邀请码，家属端输入邀请码后建立家庭关系。'),
    Figure('speaker_bind', '13_speaker_bind.png', '音箱接入', '图 4-13  小度音箱接入', '页面给出接入步骤，支持生成配对码并查看当前已连接音箱。'),
    Figure('child_home', '16_child_home_clean.png', '家属端首页', '图 5-1  家属端首页', '家属端首页展示绑定老人的用药概况、风险提示和常用操作入口。'),
    Figure('child_elder', '17_child_elder.png', '老人用药视图', '图 5-2  老人用药视图', '家属可查看绑定老人的药品、计划、告警和服药记录。'),
    Figure('family_center', '18_child_elder_detail.png', '家属中心', '图 5-3  家属中心', '集中管理绑定老人、通知设置、用药安全声明和智能音箱接入说明。'),
    Figure('bound_elders', '19_bound_elders.png', '绑定老人', '图 5-4  绑定老人账号', '家属输入老人端生成的有效邀请码，建立照护关系并查看授权范围内的数据。'),
]


def ensure_dirs() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)


def set_run_font(run, font: str = BODY_FONT, size: float | None = None, bold: bool | None = None, color: str | None = None) -> None:
    run.font.name = font
    run._element.rPr.rFonts.set(qn('w:eastAsia'), font)
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if color is not None:
        run.font.color.rgb = RGBColor.from_string(color)


def set_paragraph_format(p, before: float = 0, after: float = 6, line: float | None = None, align=None) -> None:
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    if line is not None:
        p.paragraph_format.line_spacing = Pt(line)
    if align is not None:
        p.alignment = align


def add_text(doc, text: str, *, style: str | None = None, size: float = 11, bold: bool = False,
             align=None, before: float = 0, after: float = 6, font: str = BODY_FONT,
             line: float | None = None, color: str | None = None):
    p = doc.add_paragraph(style=style)
    set_paragraph_format(p, before=before, after=after, line=line, align=align)
    r = p.add_run(text)
    set_run_font(r, font=font, size=size, bold=bold, color=color)
    return p


def add_bullet(doc, text: str, level: int = 0):
    p = doc.add_paragraph()
    set_paragraph_format(p, after=3)
    prefix = '• ' if level == 0 else '  - '
    r = p.add_run(prefix + text)
    set_run_font(r, size=11)
    return p


def add_page_break(doc):
    p = doc.add_paragraph()
    p.add_run().add_break(WD_BREAK.PAGE)
    return p


def add_field(paragraph, instruction: str, placeholder: str = '1') -> None:
    run = paragraph.add_run()
    begin = OxmlElement('w:fldChar')
    begin.set(qn('w:fldCharType'), 'begin')
    instr = OxmlElement('w:instrText')
    instr.set(qn('xml:space'), 'preserve')
    instr.text = instruction
    separate = OxmlElement('w:fldChar')
    separate.set(qn('w:fldCharType'), 'separate')
    text = OxmlElement('w:t')
    text.text = placeholder
    end = OxmlElement('w:fldChar')
    end.set(qn('w:fldCharType'), 'end')
    run._r.extend([begin, instr, separate, text, end])


def clear_document(doc: Document) -> None:
    body = doc._element.body
    for child in list(body):
        if child.tag != qn('w:sectPr'):
            body.remove(child)


def configure_styles(doc: Document) -> None:
    normal = doc.styles['Normal']
    normal.font.name = BODY_FONT
    normal.font.size = Pt(11)
    normal._element.rPr.rFonts.set(qn('w:eastAsia'), BODY_FONT)
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.25

    for name, size, color in [('Heading 1', 16, '000000'), ('Heading 2', 14, '000000'), ('Heading 3', 12, '000000')]:
        style = doc.styles[name]
        style.font.name = HEAD_FONT
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = RGBColor.from_string(color)
        style._element.rPr.rFonts.set(qn('w:eastAsia'), HEAD_FONT)
        ppr = style._element.get_or_add_pPr()
        for numpr in ppr.findall(qn('w:numPr')):
            ppr.remove(numpr)

    if 'FigureTitle' not in [s.name for s in doc.styles]:
        fig_style = doc.styles.add_style('FigureTitle', WD_STYLE_TYPE.PARAGRAPH)
    else:
        fig_style = doc.styles['FigureTitle']
    fig_style.font.name = HEAD_FONT
    fig_style.font.size = Pt(14)
    fig_style.font.bold = True
    fig_style.font.color.rgb = RGBColor.from_string('000000')
    fig_style._element.rPr.rFonts.set(qn('w:eastAsia'), HEAD_FONT)
    fig_ppr = fig_style._element.get_or_add_pPr()
    for outline in fig_ppr.findall(qn('w:outlineLvl')):
        fig_ppr.remove(outline)

    if 'CodeLine' not in [s.name for s in doc.styles]:
        code = doc.styles.add_style('CodeLine', WD_STYLE_TYPE.PARAGRAPH)
    else:
        code = doc.styles['CodeLine']
    code.font.name = CODE_FONT
    code.font.size = Pt(8)
    code._element.rPr.rFonts.set(qn('w:eastAsia'), CODE_FONT)
    code.paragraph_format.space_before = Pt(0)
    code.paragraph_format.space_after = Pt(0)
    code.paragraph_format.line_spacing = Pt(10.6)
    code.paragraph_format.keep_together = True


def configure_header(section, title: str) -> None:
    headers = [section.header, section.first_page_header, section.even_page_header]
    for header in headers:
        for p in list(header.paragraphs):
            p._element.getparent().remove(p._element)
        p = header.add_paragraph()
        set_paragraph_format(p, after=0, line=12)
        p.paragraph_format.tab_stops.add_tab_stop(Inches(6.9), WD_TAB_ALIGNMENT.RIGHT)
        r = p.add_run(title + '\t')
        set_run_font(r, HEAD_FONT, 8.5, False, '000000')
        r2 = p.add_run('第 ')
        set_run_font(r2, HEAD_FONT, 8.5, False, '000000')
        add_field(p, ' PAGE ', '1')
        r3 = p.add_run(' 页 / 共 ')
        set_run_font(r3, HEAD_FONT, 8.5, False, '000000')
        add_field(p, ' NUMPAGES ', '1')
        r4 = p.add_run(' 页')
        set_run_font(r4, HEAD_FONT, 8.5, False, '000000')
    section.different_first_page_header_footer = False


def prepare_image(fig: Figure) -> Path:
    src = SCREENS / fig.source
    im = Image.open(src).convert('RGB')
    top = min(fig.crop_top, max(0, im.height - 200))
    bottom = max(0, im.height - fig.crop_bottom)
    im = im.crop((0, top, im.width, bottom))
    # A light frame keeps phone screenshots visually separate from the white page.
    canvas = Image.new('RGB', (im.width + 32, im.height + 32), (241, 245, 249))
    canvas.paste(im, (16, 16))
    d = ImageDraw.Draw(canvas)
    d.rectangle((16, 16, 16 + im.width - 1, 16 + im.height - 1), outline=(210, 220, 232), width=2)
    out = ASSETS / f'{fig.key}.png'
    canvas.save(out, quality=95)
    return out


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = r'C:\Windows\Fonts\simsun.ttc'
    return ImageFont.truetype(path, size)


def rounded_box(draw: ImageDraw.ImageDraw, box, fill, outline, radius=18, width=3):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def wrap_text(draw, text, fnt, max_width):
    lines = []
    current = ''
    for ch in text:
        trial = current + ch
        if draw.textbbox((0, 0), trial, font=fnt)[2] <= max_width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = ch
    if current:
        lines.append(current)
    return lines


def create_architecture_diagram(path: Path) -> None:
    w, h = 1800, 1120
    im = Image.new('RGB', (w, h), 'white')
    d = ImageDraw.Draw(im)
    title_f = font(40, True)
    layer_f = font(27, True)
    item_f = font(22)
    d.text((70, 30), f'{APP_NAME} 系统架构', font=title_f, fill=(0, 0, 0))
    layers = [
        ('用户层', (245, 245, 245), (70, 70, 70), ['老人端 Android App', '家属端 Android App', '小度智能音箱']),
        ('应用功能层', (238, 238, 238), (70, 70, 70), ['注册登录 / 家庭绑定', '药品建档 / 库存有效期', 'AI 识药 / 说明书解析', '用药计划 / 服药确认', '提醒中心 / 语音助手']),
        ('服务与接口层', (230, 230, 230), (70, 70, 70), ['FastAPI 接口', 'JWT 认证与家庭权限', '业务规则与审计日志', '智谱视觉/文本模型适配', 'DuerOS 语音意图']),
        ('数据层', (220, 220, 220), (70, 70, 70), ['SQLModel 数据模型', 'SQLite 数据库', '配置与密钥环境变量']),
    ]
    y = 125
    for name, fill, outline, items in layers:
        box_h = 138 if name != '应用功能层' else 178
        rounded_box(d, (70, y, 430, y + box_h), fill, outline, radius=24, width=4)
        d.text((120, y + 35), name, font=layer_f, fill=(0, 0, 0))
        x = 465
        item_w = int((1250 - (len(items)-1)*18) / len(items))
        for item in items:
            rounded_box(d, (x, y + 25, x + item_w, y + box_h - 25), 'white', outline, radius=18, width=3)
            lines = wrap_text(d, item, item_f, item_w - 28)
            total_h = len(lines) * 31
            yy = y + box_h//2 - total_h//2
            for line in lines:
                tw = d.textbbox((0,0), line, font=item_f)[2]
                d.text((x + (item_w-tw)//2, yy), line, font=item_f, fill=(0, 0, 0))
                yy += 31
            x += item_w + 18
        if y < 905:
            d.line((900, y + box_h, 900, y + box_h + 25), fill=(70,70,70), width=4)
            d.polygon([(900, y+box_h+25),(888,y+box_h+10),(912,y+box_h+10)], fill=(70,70,70))
        y += box_h + 25
    im.save(path)


def create_business_flow(path: Path) -> None:
    w, h = 1800, 880
    im = Image.new('RGB', (w, h), 'white')
    d = ImageDraw.Draw(im)
    title_f = font(40, True)
    f = font(24, True)
    small = font(19)
    d.text((70, 30), f'{APP_NAME} 核心业务流程', font=title_f, fill=(0, 0, 0))
    steps = [
        ('1. 登录/注册', '建立老人或家属账号'),
        ('2. 录入药品', '拍照识药或人工录入'),
        ('3. 人工确认', '核对名称、剂量和有效期'),
        ('4. 设置计划', '选择药品、时间和剂量'),
        ('5. 到点提醒', '本地通知与音箱播报'),
        ('6. 服药确认', '记录服药并扣减库存'),
        ('7. 风险告警', '库存、过期、漏服提醒'),
    ]
    x0, y0 = 70, 210
    box_w, box_h, gap = 224, 170, 24
    for i, (title, desc) in enumerate(steps):
        x = x0 + i * (box_w + gap)
        fill = (245, 245, 245) if i % 2 == 0 else (235, 235, 235)
        outline = (70, 70, 70)
        rounded_box(d, (x, y0, x+box_w, y0+box_h), fill, outline, radius=22, width=4)
        d.text((x+20, y0+22), title, font=f, fill=(35, 55, 75))
        yy = y0 + 72
        for line in wrap_text(d, desc, small, box_w-40):
            d.text((x+20, yy), line, font=small, fill=(0, 0, 0))
            yy += 27
        if i < len(steps)-1:
            ax = x + box_w
            d.line((ax+5, y0+box_h//2, ax+gap-5, y0+box_h//2), fill=(70,70,70), width=4)
            d.polygon([(ax+gap-5, y0+box_h//2),(ax+gap-18,y0+box_h//2-10),(ax+gap-18,y0+box_h//2+10)], fill=(70,70,70))
    d.text((70, 500), '数据沉淀', font=font(28, True), fill=(31,78,121))
    rounded_box(d, (70, 555, 1730, 770), (248, 250, 252), (180,190,200), radius=20, width=3)
    d.text((105, 590), '药品档案  |  用药计划  |  服药记录  |  库存与有效期  |  风险告警  |  家庭关系  |  操作审计', font=font(25), fill=(0, 0, 0))
    d.text((105, 660), '所有核心数据由服务端统一保存，老人与家属按账号权限访问；AI 识别结果必须人工复核。', font=font(22), fill=(0, 0, 0))
    im.save(path)


def clean_python_source(path: Path) -> list[str]:
    source = path.read_text(encoding='utf-8')
    lines = source.splitlines()
    masks: list[list[tuple[int, int]]] = [[] for _ in lines]
    previous_type = tokenize.ENCODING
    for tok in tokenize.generate_tokens(io.StringIO(source).readline):
        if tok.type == tokenize.COMMENT:
            row = tok.start[0] - 1
            if 0 <= row < len(masks):
                masks[row].append((tok.start[1], tok.end[1]))
        elif tok.type == tokenize.STRING and tok.string.strip().startswith(('"""', "'''")):
            if previous_type in {tokenize.ENCODING, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT}:
                for row in range(tok.start[0] - 1, min(tok.end[0], len(lines))):
                    start_col = tok.start[1] if row == tok.start[0] - 1 else 0
                    end_col = tok.end[1] if row == tok.end[0] - 1 else len(lines[row])
                    masks[row].append((start_col, end_col))
        if tok.type not in {tokenize.NL, tokenize.COMMENT, tokenize.ENCODING}:
            previous_type = tok.type
    cleaned = []
    for line, ranges in zip(lines, masks):
        chars = list(line)
        for start_col, end_col in ranges:
            for i in range(max(0, start_col), min(len(chars), end_col)):
                chars[i] = ' '
        value = ''.join(chars).rstrip()
        if value.strip():
            cleaned.append(value)
    return cleaned
def clean_dart_source(path: Path) -> list[str]:
    source = path.read_text(encoding='utf-8')
    source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    lines = []
    for line in source.splitlines():
        line = re.sub(r'^\s*//.*$', '', line)
        line = re.sub(r'\s+//.*$', '', line).rstrip()
        if line.strip():
            lines.append(line)
    return lines


EMOJI_RE = re.compile('[🀀-🫿☀-➿⬀-⯿️‍]')
KAOMOJI_RE = re.compile(r'(?<![A-Za-z0-9_])(?:\^_?\^|>_<|T_T|Q_Q|Orz|orz|:\)|:\(|:D|;P|=\)|=\()(?![A-Za-z0-9_])')


def sanitize_line(line: str) -> str:
    line = EMOJI_RE.sub('', line)
    line = ''.join(ch for ch in line if unicodedata.category(ch) not in {'So', 'Sk', 'Cf'})
    line = KAOMOJI_RE.sub('', line)
    replacements = {
        'https://smart-medicine-box.124.156.137.131.nip.io': 'https://example.invalid',
        'dev-only-change-this-secret': '<redacted-secret>',
        '13800000000': '<demo-phone-1>',
        '13900000000': '<demo-phone-2>',
        '123456': '<demo-password>',
        'Demo Pharma': 'Demo Pharma',
    }
    for old, new in replacements.items():
        line = line.replace(old, new)
    line = re.sub(r'(?i)(api[_-]?key\s*[=:]\s*)[\'"][^\'"]+[\'"]', r"\1'<redacted>'", line)
    line = re.sub(r'(?i)(jwt[_-]?secret\s*[=:]\s*)[\'"][^\'"]+[\'"]', r"\1'<redacted>'", line)
    line = re.sub(r'(?i)(password\s*[=:]\s*)[\'"][^\'"]+[\'"]', r"\1'<redacted>'", line)
    line = re.sub(r'\b[a-f0-9]{32,}\b', '<redacted>', line)
    return line


def split_long_line(line: str, limit: int = 104) -> list[str]:
    if len(line) <= limit:
        return [line]
    parts: list[str] = []
    remaining = line
    while len(remaining) > limit:
        cut = remaining.rfind(' ', 0, limit + 1)
        if cut < 60:
            cut = limit
        parts.append(remaining[:cut].rstrip())
        remaining = remaining[cut:].lstrip()
    if remaining:
        parts.append(remaining)
    return parts


def collect_code_lines() -> list[str]:
    files = sorted(list((ROOT / 'backend' / 'app').glob('*.py')) + list((ROOT / 'frontend' / 'lib').rglob('*.dart')))
    lines: list[str] = []
    for path in files:
        if path.name == '__init__.py' and path.stat().st_size < 100:
            continue
        raw = clean_python_source(path) if path.suffix == '.py' else clean_dart_source(path)
        for line in raw:
            line = sanitize_line(line.strip('\ufeff'))
            if line.strip():
                lines.extend(split_long_line(line))
    return lines


def add_toc(doc: Document) -> None:
    p = doc.add_paragraph()
    set_paragraph_format(p, after=6)
    add_field(p, ' TOC \\o "1-3" \\h \\z \\u ', '目录将在打开文档后自动更新')


def add_figure_page(doc: Document, fig: Figure, image_path: Path) -> None:
    add_page_break(doc)
    add_text(doc, fig.title, style='FigureTitle', font=HEAD_FONT, size=14, bold=True, before=0, after=4)
    add_text(doc, fig.description, size=10.5, after=5)
    p = doc.add_paragraph()
    set_paragraph_format(p, align=WD_ALIGN_PARAGRAPH.CENTER, after=4)
    p.add_run().add_picture(str(image_path), width=Inches(3.28))
    add_text(doc, fig.caption, size=10, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER, after=0)


def add_wide_figure_page(doc: Document, title: str, caption: str, description: str, image_path: Path) -> None:
    add_page_break(doc)
    add_text(doc, title, style='FigureTitle', font=HEAD_FONT, size=14, bold=True, before=0, after=4)
    add_text(doc, description, size=10.5, after=5)
    p = doc.add_paragraph()
    set_paragraph_format(p, align=WD_ALIGN_PARAGRAPH.CENTER, after=4)
    p.add_run().add_picture(str(image_path), width=Inches(6.15))
    add_text(doc, caption, size=10, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER, after=0)


def build_manual(fig_paths: dict[str, Path]) -> Path:
    doc = Document(str(MANUAL_TEMPLATE))
    clear_document(doc)
    configure_styles(doc)
    configure_header(doc.sections[0], f'{APP_NAME} {VERSION} 操作手册')

    # 封面
    p = doc.add_paragraph()
    set_paragraph_format(p, before=36, after=12, align=WD_ALIGN_PARAGRAPH.CENTER)
    im = Image.open(SCREENS / '01_login.png')
    icon = im.crop((330, 130, 750, 610))
    icon_path = ASSETS / 'cover_icon.png'
    icon.save(icon_path)
    p.add_run().add_picture(str(icon_path), width=Inches(1.35))
    add_text(doc, APP_NAME, size=26, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER, font=HEAD_FONT, before=16, after=4)
    add_text(doc, VERSION, size=18, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER, font=HEAD_FONT, after=22)
    add_text(doc, '操作手册', size=28, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER, font=HEAD_FONT, after=16)
    add_text(doc, '软件著作权登记申请材料', size=14, align=WD_ALIGN_PARAGRAPH.CENTER, after=48)
    add_text(doc, 'XXXX年XX月', size=12, align=WD_ALIGN_PARAGRAPH.CENTER, after=0)

    # 目录
    add_page_break(doc)
    add_text(doc, '目录', font=HEAD_FONT, size=18, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER, after=12)
    add_toc(doc)

    # 第1章 引言
    add_page_break(doc)
    doc.add_heading('第1章 引言', level=1)
    doc.add_heading('1.1 编写背景', level=2)
    add_text(doc, '随着我国人口老龄化程度不断提高，居家养老已经成为许多家庭的重要生活场景。老年人往往同时患有高血压、糖尿病、心脑血管疾病等慢性疾病，需要长期服用一种或多种药品。由于药品名称、规格、剂量、服用时间和有效期各不相同，老人及其家属仅依靠记忆或纸质便签进行管理，容易出现漏服、重复服用、过期药未及时处理以及库存不足等情况。')
    add_text(doc, '传统家庭用药管理通常采用药盒分类、手写记录、手机备忘录或家属口头提醒等方式。这些方式在药品数量较少时较为简单，但随着药品数量和服用周期增加，药品信息容易分散在多个位置，服药记录无法连续保存，库存和有效期需要人工检查，家属也难以远程了解老人的实际执行情况。')
    add_text(doc, '为降低家庭用药管理过程中的信息遗漏风险，提高老人按时用药和家属协同照护的便利性，本项目开发了一套面向老人和家属的移动应用。软件通过药品建档、拍照识药、说明书解析、用药计划、到点提醒、服药确认、库存告警和家庭绑定等功能，将家庭用药过程中的关键数据进行统一管理。')
    fig_overview = Figure('elder_home', FIGURES[2].source, '软件概览图', '图 1-1  软件概览图', '智享药箱家庭用药管理系统首页。')
    add_figure_page(doc, fig_overview, fig_paths[fig_overview.key])

    add_page_break(doc)
    doc.add_heading('1.2 开发目的', level=2)
    add_text(doc, f'{APP_NAME} {VERSION} 的开发目标是针对居家老人用药信息分散、提醒不及时、服药记录不完整和家属协同困难等问题，建立一套操作简单、信息集中、过程可追踪的家庭用药管理系统。软件以药品档案为基础，以用药计划为主线，以提醒和服药记录为执行依据，并通过风险告警帮助用户及时发现库存不足、药品临期和漏服等情况。')
    for item in ['建立统一的药品档案，集中保存药品名称、用法用量、库存和有效期等信息。', '通过拍照识药和说明书解析减少手工录入，提高药品建档效率。', '通过用药计划、到点提醒和服药确认形成完整的用药执行流程。', '通过库存、有效期和漏服告警帮助用户及时处理潜在风险。', '通过家庭绑定和权限隔离，让家属在授权范围内了解老人的用药情况。', '通过语音助手和小度音箱提供适合老年用户的交互方式。']:
        add_bullet(doc, item)
    add_text(doc, '软件在实现过程中坚持“辅助管理、人工确认”的原则，AI 识别结果不作为最终用药依据，用户仍需结合药品说明书、医生或药师意见进行核对。软件只提供信息记录、提醒和辅助识别功能，不替代医疗诊断和处方。')
    add_wide_figure_page(doc, '业务流程图', '图 1-2  业务流程图', '软件主流程包括账号登录、药品录入、人工确认、计划设置、到点提醒、服药确认和风险告警。', ASSETS / 'business-flow.png')

    add_page_break(doc)
    doc.add_heading('1.3 定义与缩略语', level=2)
    add_text(doc, '为使文档中的技术名词和业务术语保持一致，本手册对以下常用术语进行说明。软件使用过程中涉及的相关概念，均以本节定义为准。')
    add_text(doc, '本手册中出现“老人端”时，指以老人账号登录后的功能界面；“家属端”指家属账号登录后用于查看绑定老人和进行照护协同的界面。API、JWT 等术语仅用于说明系统实现方式，不影响用户的基本操作。')
    glossary = [
        ('Android', '移动端运行平台，用户通过安装 APK 使用软件。'),
        ('APK', 'Android 应用安装包，用于将软件安装到手机或平板设备。'),
        ('API', '应用程序编程接口，用于移动端与后端服务之间进行数据交互。'),
        ('JWT', 'JSON Web Token，用于保存和验证用户登录状态。'),
        ('AI', '人工智能，本软件主要用于药盒图像识别和说明书文本解析。'),
        ('SQLite', '后端使用的轻量级关系数据库，用于保存用户、药品、计划和服药记录等数据。'),
    ]
    table = doc.add_table(rows=1, cols=2)
    table.style = 'Table Grid'
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.rows[0].cells[0].text = '术语'
    table.rows[0].cells[1].text = '说明'
    for term, desc in glossary:
        cells = table.add_row().cells
        cells[0].text = term
        cells[1].text = desc
    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                for r in p.runs:
                    set_run_font(r, size=10.5)

    # 第2章 软件概述
    add_page_break(doc)
    doc.add_heading('第2章 软件概述', level=1)
    doc.add_heading('2.1 软件名称与版本', level=2)
    add_text(doc, f'软件全称：{APP_NAME}。')
    add_text(doc, f'软件简称：{SHORT_NAME}。')
    add_text(doc, f'版本号：{VERSION}。')
    add_text(doc, '版本性质：V1.0 为软件首个正式版本，已实现用户注册登录、药品建档、AI 识药、说明书解析、用药计划、服药提醒、服药记录、风险告警、家庭绑定、语音助手和小度音箱接入等主要功能。软件适用于 Android 移动设备，并通过后端服务统一保存业务数据。')
    doc.add_heading('2.2 开发技术', level=2)
    doc.add_heading('2.2.1 编程语言、语言环境', level=3)
    add_text(doc, '软件采用移动端与后端分离的开发方式。移动端主要负责界面展示、用户交互、权限申请、本地通知和语音入口；后端主要负责用户身份认证、家庭权限校验、药品与计划管理、服药记录、风险判断和模型接口调用。')
    for item in ['开发环境：Windows 与 Linux 环境下进行移动端和后端开发。', '编程语言：移动端使用 Dart，后端使用 Python 和 SQL。', '运行框架：移动端使用 Flutter，后端使用 FastAPI、SQLModel 和 Uvicorn。', '界面技术：移动端采用 Flutter Material 组件，并根据老年用户特点放大字号和触控区域。', '核心技术：JWT 认证、数据库模型、家庭权限、通知服务、AI 视觉模型和文本模型调用。', '配置与资源：数据库地址、JWT 密钥和模型 API Key 通过环境变量或密钥管理服务提供。']:
        add_bullet(doc, item)
    doc.add_heading('2.2.2 运行环境', level=3)
    for item in ['客户端硬件最低配置：Android 8.0 及以上设备，2GB 及以上内存，100MB 以上可用空间，并具备网络连接。', '客户端软件环境：Android 操作系统；拍照识药需要相机权限，语音功能需要麦克风权限，提醒功能需要通知权限。', '服务端硬件最低配置：1 核 CPU、2GB 内存、5GB 可用硬盘空间。', '服务端软件环境：Python 3.10 及以上、SQLite，推荐使用 Linux 服务器并提供 HTTPS 访问。', '网络环境：客户端需要访问后端接口；AI 识药和说明书解析功能需要后端能够访问对应模型服务。']:
        add_bullet(doc, item)
    doc.add_heading('2.3 应用领域', level=2)
    add_text(doc, '本软件主要应用于居家养老、家庭健康管理、慢病日常用药提醒、家属远程照护和社区养老辅助等场景，服务对象包括居家老人、老人家属、照护人员以及开展社区健康服务的相关工作人员。')
    add_text(doc, '典型使用场景包括老人自行维护日常药品档案、家属帮助老人录入药品、家属远程查看老人服药完成情况、老人通过语音询问今日用药和药品库存、系统对临期药品和库存不足进行提醒等。软件既适用于单人使用，也适用于老人与多名家属共同使用的家庭场景。')
    add_text(doc, '软件在业务中主要承担信息记录、提醒和辅助识别作用，帮助家庭提高药品信息维护和服药过程管理的规范性。软件不替代医生诊断、处方、药师指导或药品说明书，涉及具体用药方案时应遵循专业医疗意见。')
    add_text(doc, '对于存在多种基础疾病、使用处方药或需要特殊剂量调整的用户，软件仅记录其自行维护的信息，不根据疾病名称自动推荐药品，也不根据历史数据调整剂量。')
    doc.add_heading('2.4 软件特点', level=2)
    add_text(doc, '软件围绕老年用户的使用习惯进行设计，主要页面采用较大字号、较高对比度和较大的操作区域。首页集中展示今日服药、药品数量、计划数量、风险告警和下一次提醒等关键信息，用户无需进入多个页面即可了解当天用药情况。')
    add_text(doc, '软件将药品、计划、提醒、服药记录和风险告警进行关联管理。当用户创建药品和用药计划后，系统可以根据计划触发提醒；用户确认服药后，系统自动保存记录并扣减库存；当库存不足或药品临近有效期时，系统在提醒中心集中展示风险信息。')
    add_text(doc, '软件还提供拍照识药、说明书解析、家庭绑定和语音交互等辅助功能。AI 识别结果必须经过人工确认，家属只能访问已绑定老人的数据。通过数据关联、权限控制和人工复核机制，软件能够兼顾使用便利性与信息安全。')
    add_text(doc, '软件还考虑了网络不可用、识别失败、权限关闭和重复确认等异常场景。出现异常时，界面会给出对应提示，用户可以改为手动录入、重新操作或稍后重试。')

    # 第3章 软件安装（或者登录）
    add_page_break(doc)
    doc.add_heading('第3章 软件安装（或者登录）', level=1)
    add_text(doc, '软件以 Android APK 形式发布。安装前应确认设备系统版本、存储空间和网络连接满足要求。首次启动时，用户可根据实际需要授予通知、相机或麦克风权限；不需要某项功能时，可以拒绝相应权限，已保存的手动数据不会受到影响。')
    add_text(doc, '安装完成后，用户进入登录页面。已有账号可直接输入手机号和密码登录；新用户可点击注册入口，选择老人端或家属端角色并填写注册信息。登录成功后，系统根据用户角色展示对应界面，并建立用户与服务端之间的访问令牌。')
    for i, text in enumerate(['取得正式 APK 安装包。', '在 Android 设备上允许安装未知应用，点击 APK 并按照系统提示完成安装。', '启动软件，已有账号直接输入手机号和密码登录；新用户点击“立即注册”。', '注册时选择老人端或家属端角色，填写手机号、昵称、密码和确认密码。'], 1):
        add_text(doc, f'{i}. {text}', after=4)
    fig_login = Figure('login', FIGURES[0].source, '软件登录', '图 3-1  软件登录', '软件登录页面。')
    add_figure_page(doc, fig_login, fig_paths[fig_login.key])

    # 第4章 软件功能描述
    add_page_break(doc)
    doc.add_heading('第4章 软件功能描述', level=1)
    doc.add_heading('4.1 核心功能详述', level=2)
    add_text(doc, '软件功能围绕家庭用药管理全过程进行设计，主要包括账号管理、首页概览、药品管理、AI 识药、说明书解析、用药计划、服药确认、风险告警、家庭绑定、语音助手和音箱接入等内容。各功能模块之间通过用户、药品、计划和服药记录等数据建立关联，形成连续的用药管理流程。')

    functions = [
        ('4.1.1 用户注册与登录功能',
         ['软件提供老人端和家属端两种账号角色。用户在注册页面输入手机号、昵称、密码和确认密码，并选择对应角色后完成注册。系统对手机号格式、密码长度和密码一致性进行检查，注册成功后返回登录状态和用户信息。',
          '用户登录时，系统校验手机号、密码和账号状态。认证成功后生成访问令牌，后续药品、计划、提醒和家庭关系等接口均通过令牌验证身份。家属账号只能在绑定老人后访问授权范围内的数据，老人账号默认管理本人的药品和用药计划。']),
        ('4.1.2 首页与用药概览功能',
         ['首页是用户进入软件后的主要信息入口，集中展示今日服药进度、药品数量、计划数量、告警数量和下一次提醒。今日服药区域显示计划总数、已完成数量和待确认数量，用户可以通过首页快速判断当天是否存在未完成用药。',
          '首页还提供拍照识药、用药计划、添加计划、药品管理和语音助手等快捷入口。当存在库存不足、临近有效期或漏服情况时，首页和提醒中心会显示告警信息。家属端可以切换查看自己的用药情况或已绑定老人的用药情况。']),
        ('4.1.3 药品信息管理功能',
         ['药品管理模块用于保存家庭药品的基础资料。用户可以录入药品名称、分类、厂家、用法用量、注意事项、库存数量、库存提醒阈值和有效期等信息。药品列表支持按全部、正常、临期和过期状态进行筛选，并使用不同颜色标识药品状态。',
          '用户点击药品卡片后可以查看药品详情，核对厂家、用法用量、有效期、库存、提醒数量和注意事项。药品资料既可以手动录入，也可以通过拍照识药或说明书解析辅助生成。药品库存会在确认服药后自动扣减，用户也可以根据实际情况调整库存和提醒阈值。']),
        ('4.1.4 AI 拍照识药功能',
         ['拍照识药功能用于降低药盒信息录入成本。用户可以直接拍摄药盒正面，也可以从相册中选择已有图片。系统将图片上传至后端，由视觉模型识别药品名称、规格、厂家和用法等可见信息，并返回结构化识别结果。',
          '为保证用药安全，识别结果不会直接写入药品档案。软件会进入人工确认页面，用户可以修改药品名称、用法用量、有效期和注意事项，确认无误后再保存。对于置信度较低、图片不清晰或模型无法确认的结果，系统会要求用户手动填写。']),
        ('4.1.5 说明书解析功能',
         ['说明书解析功能用于从药品说明书中提取需要长期保存的用药信息。用户可以复制说明书中的用法用量、禁忌、注意事项等内容并粘贴到解析窗口，系统通过文本模型提取关键信息，辅助生成药品说明。',
          '解析结果会与药品档案一起展示，用户可以继续编辑和核对。系统不会使用模型结果替代说明书原文，涉及禁忌、特殊人群和不良反应等内容时，用户仍应以纸质说明书、医生或药师意见为准。']),
        ('4.1.6 用药计划管理功能',
         ['用药计划模块用于建立药品与服用时间之间的关系。用户在新增计划时选择需要管理的药品，系统自动使用药品名称作为计划标题，并设置每天重复或指定日期、提醒时间和每次剂量。剂量可以选择半片、一片、两片、一袋、两袋或具体毫升数，也可以手动输入特殊剂量。',
          '计划创建后，用户可以在列表中查看药品名称、日期、提醒时间和剂量，并可进入编辑页面调整药品、日期、时间或剂量。用户可以删除不再需要的计划，删除后系统同步撤销本地通知。系统根据计划触发提醒，通知正文包含药品名称、剂量和服药时间。']),
        ('4.1.7 服药提醒与确认功能',
         ['到达计划提醒时间后，软件通过系统通知提示用户服药。老人也可以使用小度音箱接收语音提醒。用户完成服药后，可以在提醒页面或计划页面进行确认，系统记录实际服药时间、药品、剂量和所属用户。',
          '服药确认成功后，系统同步扣减对应药品库存，并更新今日服药进度。软件会对重复确认进行检查，避免用户在短时间内多次点击造成重复记账。如果计划时间已过但尚未确认，提醒中心会显示漏服或待核实提示。']),
        ('4.1.8 风险告警功能',
         ['风险告警功能根据药品库存、有效期和用药计划生成提示。当药品剩余数量低于用户设置的提醒阈值时，系统显示库存不足告警；当药品有效期接近当前日期或已经过期时，系统显示有效期告警；当计划时间过后仍未确认服药时，系统显示漏服风险。',
          '提醒中心集中展示上述风险，并显示今日服药记录和处理入口。用户可以修改库存提醒数量、更新药品库存或调整计划。告警信息用于提醒用户及时核对和处理，不构成医疗建议。']),
        ('4.1.9 家庭绑定功能',
         ['家庭绑定功能用于建立老人账号与家属账号之间的照护关系。老人端可以生成具有有效期的邀请码，家属端输入邀请码后完成绑定。绑定成功后，家属可以在授权范围内查看老人的药品、用药计划和服药记录。',
          '系统通过用户角色、家庭关系和数据所属人进行访问控制。家属只能查看已绑定老人的数据，不能访问其他家庭的信息。老人可以重新生成邀请码，家属也可以在需要时重新建立绑定关系。']),
        ('4.1.10 语音助手与音箱接入功能',
         ['语音助手支持用户通过语音或文字询问今日用药、药品用法、库存、有效期和确认服药等问题。系统先对 ASR 文本进行药名和别名纠错，再通过规则意图识别今日用药、库存、有效期和确认服药等任务，并结合用户药品记录、计划和说明书资料组织回答。',
          '语音助手对未命中固定规则的问题提供受控 AI 兜底，但模型只能使用服务端提供的用药资料，不得凭记忆补充剂量、禁忌或相互作用。诊断、换药、加量、儿童孕妇用药和急症等高风险问题会被拦截；确认服药等写操作必须先返回确认提示，用户再次确认后才写入数据库。老人端还可以生成音箱配对码，将小度音箱接入当前账号。']),
    ]
    function_notes = {
        '4.1.1 用户注册与登录功能': '注册信息会保存到服务端，密码以不可逆摘要形式存储；移动端仅保存访问令牌和必要的当前用户信息。用户注销后，本地令牌会被清除。',
        '4.1.2 首页与用药概览功能': '首页数据由药品、计划、服药记录和告警接口汇总生成。若页面数据未及时更新，用户可以下拉刷新或重新进入首页。',
        '4.1.3 药品信息管理功能': '药品删除前应确认没有仍需使用的计划；历史服药记录不会因用户删除设备缓存而丢失，正式数据以服务端保存结果为准。',
        '4.1.4 AI 拍照识药功能': '图片仅用于本次识别，后端应在完成处理后删除临时文件。对于包装反光、文字缺失或存在多个药品名称的图片，建议重新拍摄。',
        '4.1.5 说明书解析功能': '解析结果只作为录入辅助，用户应将提取内容与说明书原文逐项核对；无法确认的禁忌和特殊人群信息不应自行推断。',
        '4.1.6 用药计划管理功能': '计划标题与所选药品名称保持一致。每天计划和指定日期计划使用相同的药品、时间和剂量字段，指定日期到期后不会继续生成新的提醒；删除计划后同步撤销本地通知。',
        '4.1.7 服药提醒与确认功能': '不同手机厂商对后台通知限制不同，用户应按照系统提示允许必要权限。语音确认无法唯一匹配计划时，系统不会生成服药记录。',
        '4.1.8 风险告警功能': '告警只表示系统判断存在需要核对的情况，不代表医学结论。用户处理告警后，可更新库存、有效期或计划信息使页面状态恢复。',
        '4.1.9 家庭绑定功能': '邀请码具有时效性，不应公开发布。绑定关系解除后，家属端将无法继续读取老人数据，历史数据的处理应遵循双方约定和适用法律。',
        '4.1.10 语音助手与音箱接入功能': '语音识别结果和文字查询均由用户主动触发，系统不会在未授权情况下持续录音。会话上下文只保留短时间内的意图、药品和计划标识，不保存密码等敏感信息；模型只能使用数据库提供的用药资料，不能直接写数据库。',
    }
    for title, paragraphs in functions:
        doc.add_heading(title, level=3)
        for para in paragraphs:
            add_text(doc, para)
        if title in function_notes:
            add_text(doc, function_notes[title])
    fig_ai = Figure('ai_recognize', FIGURES[5].source, 'AI 拍照识药功能', '图 4-1  AI 拍照识药功能', '拍照识药页面。')
    add_figure_page(doc, fig_ai, fig_paths[fig_ai.key])
    fig_plan = Figure('schedules', FIGURES[7].source, '用药计划管理功能', '图 4-2  用药计划管理功能', '用药计划列表页面。')
    add_figure_page(doc, fig_plan, fig_paths[fig_plan.key])

    # 第5章 技术特点与创新点
    add_page_break(doc)
    doc.add_heading('第5章 技术特点与创新点', level=1)
    doc.add_heading('5.1 技术架构', level=2)
    add_text(doc, '软件采用移动端、服务端和数据层分离的架构。移动端负责页面展示、用户交互、权限申请、本地通知、语音录音和图片选择等任务；服务端负责身份认证、数据校验、业务处理、权限判断、告警计算和模型接口调用；数据层负责保存业务数据。')
    add_text(doc, '用户交互层包括登录页面、老人端首页、家属端首页、药品管理、用药计划、提醒中心、家庭绑定和语音助手等界面。用户通过移动端完成药品录入、计划维护、服药确认和信息查询，界面根据账号角色展示不同功能。')
    add_text(doc, '业务逻辑层处理用户认证、药品数据、用药计划、服药记录、库存变化、风险告警和家庭关系等核心业务。该层集中维护业务规则，避免不同页面重复处理相同逻辑，提高系统维护和扩展能力。')
    add_text(doc, '数据访问层通过统一的数据模型访问 SQLite 数据库，保存用户、药品、计划、提醒、服药记录、家庭关系、音箱关系和审计日志等信息。数据库对象之间通过用户标识和业务主键建立关联，为查询、统计和权限校验提供基础。')
    add_text(doc, '该架构使界面展示、业务规则和数据存储相互分离。移动端升级不影响后端数据结构，后端增加新接口时也可以供音箱或其他终端复用。')
    doc.add_heading('5.2 关键技术与创新点', level=2)
    technologies = [
        ('5.2.1 前后端分离技术',
         '软件采用前后端分离方式开发。Flutter 移动端通过 HTTP API 访问 FastAPI 服务，接口返回统一的数据结构，移动端负责展示和交互，服务端负责业务处理。该方式便于移动端与后端独立开发、测试和部署，也方便后续扩展其他终端。'),
        ('5.2.2 图像识别与人工复核技术',
         '药盒识别功能将图片上传到后端，通过视觉模型提取药品名称、规格和用法等信息。考虑到模型识别存在不确定性，软件强制设置人工确认环节，并针对低置信度结果给出提示。该设计在提高录入效率的同时，降低错误信息直接进入药品档案的风险。'),
        ('5.2.3 家庭数据隔离与授权技术',
         '系统为老人和家属设置不同角色。老人账号只能管理本人数据，家属账号只能查看已绑定老人的数据。后端在处理药品、计划、提醒和服药记录请求时，会同时校验当前用户、家庭关系和数据所属人，防止越权访问。'),
        ('5.2.4 药品-计划-记录关联模型',
         '软件以药品为中心建立计划、提醒和服药记录。药品与计划存在从属关系，计划用于生成提醒，服药确认用于更新记录和扣减库存。通过对象之间的关联，用户可以查看某一药品对应的计划执行情况和历史服药记录。'),
        ('5.2.5 多端提醒与语音交互技术',
         '移动端使用本地通知和精确提醒能力触发用药提醒，通知标题和正文均包含实际药品名称与剂量。老人也可以通过小度音箱进行语音查询和确认。语音链路采用药名纠错、规则意图、数据库检索、受控 AI 兜底和二次确认的分层设计，先匹配唯一的药品或计划，再执行查询或记录操作，避免因名称不明确造成误记。'),
        ('5.2.6 安全配置与审计技术',
         '服务端使用 JWT 验证用户身份，将数据库地址、JWT 密钥和模型 API Key 等敏感配置放在环境变量或密钥管理服务中。药品新增等关键操作写入审计记录，生产环境要求使用 HTTPS、限制跨域来源并配置请求频率限制。'),
    ]
    technology_notes = {
        '5.2.1 前后端分离技术': '接口层统一处理错误码和鉴权信息，移动端根据状态码显示可理解的提示，便于问题定位和后续维护。',
        '5.2.2 图像识别与人工复核技术': '模型服务不可用或识别失败时，软件保留手动录入路径，不因第三方服务异常阻断基本药品管理功能。',
        '5.2.3 家庭数据隔离与授权技术': '每次访问老人数据时，后端都会重新校验关系，而不是仅依赖客户端状态，降低越权风险。',
        '5.2.4 药品-计划-记录关联模型': '库存扣减和记录写入在同一业务处理中完成，减少记录成功但库存未更新的情况。',
        '5.2.5 多端提醒与语音交互技术': '语音确认优先使用计划编号，其次按药品名称匹配；存在多个候选计划时要求用户进一步说明。写操作通过短时会话上下文二次确认，超时后自动失效。',
        '5.2.6 安全配置与审计技术': '审计信息仅用于问题追踪和安全核查，生产环境应限制审计数据访问权限并定期备份。',
    }
    for title, text in technologies:
        doc.add_heading(title, level=3)
        add_text(doc, text)
        if title in technology_notes:
            add_text(doc, technology_notes[title])

    # 第6章 操作指南
    add_page_break(doc)
    doc.add_heading('第6章 操作指南', level=1)
    operations = [
        ('6.1 软件启动与登录',
         ['用户在 Android 设备上完成安装后，点击桌面图标启动软件。首次启动时，系统可能根据设备版本提示通知、相机或麦克风权限，用户可以根据需要使用对应功能。',
          '进入登录页面后，已有账号输入手机号和密码，点击登录；新用户点击“立即注册”，选择老人端或家属端角色，填写手机号、昵称、密码和确认密码。登录成功后，系统根据角色进入相应首页。']),
        ('6.2 软件首页使用',
         ['老人端首页显示今日服药、药品数量、计划数量、告警数量和下一次提醒。用户可点击统计区域查看药品、计划或提醒详情，也可以点击功能卡片进入对应模块。',
          '家属端首页提供“我的用药”“老人用药”和“家属中心”等入口。家属选择老人后，可以查看绑定老人的药品、计划、告警和服药情况。首页数据会随药品、计划和服药记录变化自动更新。']),
        ('6.3 药品管理操作',
         ['在首页点击“药品管理”进入药品列表。用户可以使用搜索框查找药品，也可以通过全部、正常、临期和过期标签筛选。药品卡片显示药品名称、用法摘要和有效期状态。',
          '点击药品卡片可查看详情。新增药品时填写名称、分类、厂家、用法用量、注意事项、库存和有效期等信息；保存后药品会出现在列表中。删除药品前应确认该药品没有被重要计划或历史记录使用。']),
        ('6.4 AI 拍照识药操作',
         ['进入拍照识药页面后，点击“拍照识别”调用相机，或点击“从相册选择”选择已有药盒图片。拍照时应保证药盒正面清晰、光线充足，药品名称和规格尽量完整出现在画面中。',
          '系统完成识别后进入人工确认页面。用户逐项核对药品名称、用法、有效期和注意事项，必要时手动修改。确认信息准确后点击保存；如果识别结果不可用，可以重新识别或改为手动录入。']),
        ('6.5 用药计划管理操作',
         ['在首页点击“用药计划”查看已有计划，或点击“添加计划”创建新计划。创建计划时依次选择药品，设置每天或指定日期，再选择具体时间和剂量，保存后计划标题自动使用药品名称。',
          '计划列表显示药品名称、日期、提醒时间和剂量。点击编辑按钮可以修改计划，点击删除按钮并确认后可以删除计划，同时同步撤销本地通知。指定日期计划只在所选日期提醒，每天计划继续按日重复。']),
        ('6.6 提醒中心与服药确认操作',
         ['提醒中心集中展示库存不足、临近有效期和漏服风险。用户点击告警卡片可查看详细说明，并根据提示修改库存提醒数量、更新药品或处理计划。',
          '到达提醒时间后，用户完成服药并在提醒页面确认。系统保存服药记录、扣减库存并更新今日进度。若误点确认，应尽快在记录中核对；若时间已过仍未服药，应按照实际医嘱处理，不因软件提醒擅自改变用药方案。']),
        ('6.7 家庭绑定操作',
         ['老人端进入“我的”页面，点击“绑定家属账号”，系统生成六位邀请码。邀请码具有有效期，老人可以将邀请码告知已授权的家属。',
          '家属端登录后进入“家属中心”，点击“已绑定老人”，输入邀请码并确认绑定。绑定成功后，家属可以在“老人用药”页面查看老人数据；如需解除或重新绑定，应在双方确认后操作。']),
        ('6.8 音箱接入操作',
         ['老人端进入“我的”页面，点击“音箱接入”，按照页面提示准备小度 App 和对应的智能药箱技能。点击生成配对码后，系统显示六位数字。',
          '在小度设备中打开智能药箱技能，根据语音提示输入配对码。绑定完成后，用户可以通过语音查询今日用药、药品库存或确认服药。一个音箱同一时间只能绑定一个老人账号。']),
        ('6.9 家属端操作',
         ['家属账号登录后，可以在“我的用药”中维护自己的药品和计划，也可以切换到“老人用药”查看已绑定老人的用药数据。老人用药首页显示今日服药、药品数量、计划数量、告警数量和下一次提醒。',
          '在家属中心中，用户可以查看已绑定老人、调整通知设置、阅读用药安全声明并查看音箱接入说明。家属端只能查看授权数据，如需新增或修改老人药品，应确认当前操作符合老人和家属之间的照护约定。']),
    ]
    operation_notes = {
        '6.1 软件启动与登录': '若无法登录，应检查账号、密码和网络状态；未实现找回功能时联系技术支持，不应尝试使用他人账号。',
        '6.2 软件首页使用': '首页统计以当前登录用户或已选择老人的数据为准，家属切换老人后应确认页面标题是否正确。',
        '6.3 药品管理操作': '保存药品后建议再次核对名称、剂量和有效期。软件记录只影响本软件，不改变药品实际包装上的说明。',
        '6.4 AI 拍照识药操作': '识别过程中不要重复提交，避免产生多个临时结果。保存前应确认当前药品没有被误识别为其他名称。',
        '6.5 用药计划管理操作': '设置提醒时间时应考虑老人作息和手机系统限制，避免多个计划使用完全相同的提醒时间造成通知叠加。指定日期计划过期后仍会保留在列表中，需要时可手动删除。',
        '6.6 提醒中心与服药确认操作': '确认服药应由实际执行人完成。家属代确认前应与老人核实，避免记录与实际服药不一致。',
        '6.7 家庭绑定操作': '邀请码泄露时，老人应重新生成邀请码，旧邀请码失效后不能被继续用于绑定。',
        '6.8 音箱接入操作': '如果音箱提示绑定失败，应先确认配对码未过期、账号未绑定其他音箱，并检查网络连接。',
        '6.9 家属端操作': '家属查看数据时应尊重老人隐私。新增、修改或删除老人药品前，应先取得老人或照护责任人的确认。',
    }
    for title, paragraphs in operations:
        doc.add_heading(title, level=2)
        for para in paragraphs:
            add_text(doc, para)
        if title in operation_notes:
            add_text(doc, operation_notes[title])

    # 第7章 开发周期
    add_page_break(doc)
    doc.add_heading('第7章 开发周期', level=1)
    stages = [
        ('7.1 需求分析阶段',
         ['项目初期对居家老人和家属的用药管理场景进行调研，分析药品录入、服药提醒、库存检查、有效期管理、家属远程查看和语音交互等需求。通过梳理典型使用流程，明确软件需要解决的主要问题和适用范围。',
          '在需求分析过程中，重点确认老人端与家属端的角色差异、药品与计划的数据关系、提醒触发方式、告警规则以及 AI 识药和说明书解析的边界。对于涉及医疗安全的内容，明确软件只提供辅助记录和提醒，不替代医生或药师意见。']),
        ('7.2 架构设计阶段',
         ['根据需求确定移动端、服务端和数据层分离的总体架构。移动端使用 Flutter 实现跨平台界面，服务端使用 FastAPI 提供接口，数据库使用 SQLite 保存业务数据，AI 识药和说明书解析通过服务端模型接口完成。',
          '在数据设计方面，建立用户、家庭关系、药品、提醒、服药记录、音箱绑定和审计日志等数据对象，并确定权限校验、库存扣减、有效期判断和语音意图处理等业务规则。']),
        ('7.3 功能开发阶段',
         ['按照功能模块逐步完成登录注册、老人端首页、家属端首页、药品管理、AI 识药、说明书解析、用药计划、服药提醒、服药确认、风险告警、家庭绑定、语音助手和音箱接入等功能的开发。',
          '在开发过程中同步完善接口错误处理、权限校验和移动端异常提示。AI 识别结果必须经过人工确认，服药确认优先使用计划编号，避免因药品名称重复或语音表达不明确造成误记。']),
        ('7.4 联调测试阶段',
         ['完成移动端与服务端接口联调，验证注册登录、药品新增、计划创建、提醒触发、服药确认、库存扣减、风险告警和家庭绑定等流程。测试老人账号和家属账号在不同权限下的数据访问范围。',
          '对弱网、接口失败、识别失败、权限关闭和重复确认等情况进行异常测试，并根据测试结果调整提示文字、页面状态和业务处理逻辑。']),
        ('7.5 问题修正与发布整理阶段',
         ['根据测试记录修复发现的问题，完善必要的数据校验和错误处理，整理正式版本 APK、源代码、操作手册和申请材料。对演示手机号、演示密码、默认密钥和生产接口地址等敏感信息进行脱敏处理。',
          '最终形成 V1.0 发布版本，并对软件名称、版本号、包名、源代码和操作手册进行一致性检查，确保提交材料对应同一版本。']),
    ]
    stage_notes = {
        '7.1 需求分析阶段': '需求分析结果形成软件功能清单和主要业务流程图，作为后续设计和验收依据。',
        '7.2 架构设计阶段': '架构设计阶段同时考虑接口安全、数据库备份、移动端权限和第三方模型服务异常等情况。',
        '7.3 功能开发阶段': '开发过程中对核心业务规则保留必要说明，并按模块进行自测，减少后期联调成本。',
        '7.4 联调测试阶段': '测试覆盖正常流程、异常输入、重复操作和无权限访问等情况，并对重要问题保留处理记录。',
        '7.5 问题修正与发布整理阶段': '发布前对软件名称、版本号、包名、源代码和文档进行一致性检查，并将申报文件单独归档。',
    }
    for title, paragraphs in stages:
        doc.add_heading(title, level=2)
        for para in paragraphs:
            add_text(doc, para)
        if title in stage_notes:
            add_text(doc, stage_notes[title])

    # 第8章 常见问题解答
    add_page_break(doc)
    doc.add_heading('第8章 常见问题解答', level=1)
    faq = [
        ('1. 无法登录怎么办？', '检查手机号和密码是否正确，并确认设备网络连接正常。如果服务端暂时不可用，可以稍后重试。持续无法登录时，请记录错误提示并联系技术支持。'),
        ('2. 为什么无法使用拍照识药？', '检查是否授予相机权限；如果相机不可用，可以从相册选择图片或手动录入药品。图片不清晰、药品名称被遮挡时，识别准确率会下降。'),
        ('3. AI 识别结果一定准确吗？', 'AI 识别属于辅助功能，可能存在识别偏差。软件要求用户人工确认后再保存，具体用法和禁忌应以药品说明书、医生或药师意见为准。'),
        ('4. 为什么没有收到提醒？', '请检查通知权限、精确闹钟权限和系统省电限制，并确认用药计划处于有效状态。部分手机系统需要单独允许软件在后台运行。'),
        ('5. 服药确认后库存为什么会减少？', '软件在成功记录服药后会扣减对应药品库存。如果确认记录或库存数量异常，可以在药品详情中核对并修正。'),
        ('6. 家属为什么看不到老人数据？', '家属需要先通过老人端生成的邀请码完成绑定。邀请码过期或绑定关系解除后，家属将无法继续查看老人数据。'),
    ]
    for q, a in faq:
        add_text(doc, q, bold=True, after=2)
        add_text(doc, a, after=7)

    # 第9章 技术支持
    add_page_break(doc)
    doc.add_heading('第9章 技术支持', level=1)
    add_text(doc, '软件使用过程中如发生异常，用户应先记录问题发生时间、操作步骤、页面提示、设备型号、系统版本和软件版本。反馈问题时不要提供账号密码、身份证件或与问题无关的个人信息。')
    for label in ['技术支持单位：X', '联系人：X', '联系电话：X', '电子邮箱：X', '服务时间：X']:
        add_text(doc, label)
    add_text(doc, '技术支持主要处理安装登录、功能使用、接口异常、数据展示和软件配置等相关问题。涉及具体疾病、药品选择、剂量调整和不良反应等问题，请咨询医生或药师，技术支持人员不提供医疗诊断和用药决策。')
    add_text(doc, '为避免数据泄露，请通过约定的支持渠道反馈问题，不要将数据库、密钥、完整病历或无关药品信息发送给未授权人员。生产环境应定期备份数据库，并妥善管理账号和密钥。')
    add_text(doc, '技术支持单位、联系人、电话和邮箱由软件提供方填写。未正式发布的应用应通过项目约定的内部渠道反馈问题，不应在公共平台传播安装包或测试账号。')
    add_text(doc, '使用过程中应遵循最小必要原则，不在非必要场景上传身份证、病历或其他敏感资料。与软件功能无关的数据不需要提供给技术支持人员。')

    # 第10章 著作权声明
    add_page_break(doc)
    doc.add_heading('第10章 著作权声明', level=1)
    doc.add_heading('10.1 权利归属', level=2)
    add_text(doc, f'{APP_NAME} {VERSION} 的著作权归软件著作权人所有，受《中华人民共和国著作权法》《计算机软件保护条例》及相关法律法规保护。任何单位或个人在使用本软件时，应遵守软件授权范围和相关法律规定。')
    add_text(doc, '软件著作权人：X')
    doc.add_heading('10.2 授权声明', level=2)
    add_text(doc, '未经著作权人书面许可，任何单位或个人不得擅自复制、传播、出租、出借、出售、反向工程、反汇编、修改本软件或将本软件用于未授权的商业用途。')

    out = OUT / f'{APP_NAME}_操作手册.docx'
    doc.save(out)
    return out

def build_code_doc(code_lines: list[str]) -> Path:
    doc = Document(str(CODE_TEMPLATE))
    clear_document(doc)
    configure_styles(doc)
    configure_header(doc.sections[0], f'{APP_NAME} {VERSION} 源代码')
    sect_pr = doc.sections[0]._sectPr
    for ln_num in sect_pr.findall(qn('w:lnNumType')):
        sect_pr.remove(ln_num)
    if len(code_lines) < 3000:
        raise RuntimeError(f'clean code lines not enough: {len(code_lines)}')
    selected = code_lines[:1500] + code_lines[-1500:]
    for idx, line in enumerate(selected, 1):
        if idx > 1 and (idx - 1) % 50 == 0:
            add_page_break(doc)
        p = doc.add_paragraph(style='CodeLine')
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.line_spacing = Pt(10.6)
        r = p.add_run(f'{idx:04d}  {line}')
        set_run_font(r, CODE_FONT, 8, False)
    out = OUT / f'{APP_NAME}_软件代码.docx'
    doc.save(out)
    return out


def build_info_doc() -> Path:
    doc = Document(str(MANUAL_TEMPLATE))
    clear_document(doc)
    configure_styles(doc)
    configure_header(doc.sections[0], f'{APP_NAME} {VERSION} 申请信息确认表')
    add_text(doc, f'{APP_NAME} {VERSION}', size=22, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER, font=HEAD_FONT, after=4, color='000000')
    add_text(doc, '软件著作权登记申请信息确认表', size=16, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER, font=HEAD_FONT, after=20)
    rows = [
        ('软件全称', APP_NAME, '与操作手册和源代码一致'),
        ('软件简称', SHORT_NAME, '与操作手册一致'),
        ('版本号', 'V1.0', 'APK versionName=1.0.0'),
        ('Android 包名', PACKAGE, '从 APK 读取'),
        ('安装包', APK.name, f'{APK.stat().st_size:,} 字节'),
        ('SHA-256', APK_SHA256, '用于固定申报版本'),
        ('申请人类型', 'X', '填写个人或公司'),
        ('著作权人', 'X', '个人填身份证姓名，公司填营业执照名称'),
        ('证件类型及号码', 'X', '身份证号码或统一社会信用代码'),
        ('开发者', 'X', '按实际参与人员填写'),
        ('软件开发方式', 'X', '原始取得、独立开发、委托开发、职务开发或合作开发'),
        ('开发完成日期', 'X', '按实际完成日期填写'),
        ('首次发表日期', 'X', '未发表也请填写“未发表”'),
        ('权利取得方式', 'X', '按合同、继承或原始取得等实际情况填写'),
        ('联系人', 'X', '填写申报联系人'),
        ('联系电话', 'X', '填写可联系手机或固话'),
        ('电子邮箱', 'X', '填写有效邮箱'),
        ('通信地址', 'X', '填写详细地址'),
        ('邮政编码', 'X', '填写邮编'),
        ('是否委托代理机构', 'X', '如委托，请准备代理委托书'),
        ('运行平台', 'Android 8.0+；服务端 Linux/Windows', '与操作手册一致'),
        ('开发语言', 'Dart、Python、SQL 及平台工程代码', '与源代码一致'),
        ('主要功能', '药品建档、AI 识药、说明书解析、用药计划、提醒、服药记录、家庭绑定、库存/有效期告警、语音交互', '与操作手册一致'),
    ]
    t = doc.add_table(rows=1, cols=3); t.style='Table Grid'; t.alignment=WD_TABLE_ALIGNMENT.CENTER
    heads=t.rows[0].cells; heads[0].text='项目'; heads[1].text='拟填内容'; heads[2].text='说明/待确认'
    for a,b,c in rows:
        cells=t.add_row().cells; cells[0].text=a; cells[1].text=b; cells[2].text=c
    widths=[Inches(1.6), Inches(2.65), Inches(2.3)]
    t.autofit = False
    for row in t.rows:
        for i,cell in enumerate(row.cells):
            cell.width=widths[i]
            for p in cell.paragraphs:
                for r in p.runs:
                    set_run_font(r, size=9.5, bold=(row is t.rows[0]))
    add_text(doc, '', after=4)
    add_text(doc, '重要提示：申请表、操作手册和源代码中的软件名称、版本号必须完全一致。个人申请通常只需提交操作手册和源代码；公司申请还需根据实际情况准备营业执照、职务开发、委托开发或合作开发等权属证明。', size=10.5, color='000000')
    out = OUT / f'{APP_NAME}_申请信息确认表.docx'
    doc.save(out)
    return out


def main() -> None:
    ensure_dirs()
    for fig in FIGURES:
        prepare_image(fig)
    fig_paths = {fig.key: ASSETS / f'{fig.key}.png' for fig in FIGURES}
    create_architecture_diagram(ASSETS / 'architecture.png')
    create_business_flow(ASSETS / 'business-flow.png')
    code_lines = collect_code_lines()
    print('clean code lines:', len(code_lines))
    manual = build_manual(fig_paths)
    code = build_code_doc(code_lines)
    info = build_info_doc()
    manifest = OUT / '材料清单.txt'
    manifest.write_text(
        f'软件全称：{APP_NAME}\n版本号：{VERSION}\nAndroid 包名：{PACKAGE}\nAPK：{APK}\n\n'
        f'1. {manual.name}\n2. {code.name}\n3. {info.name}\n\n'
        '说明：操作手册包含实际 V1.0 界面截图；软件代码为前后端去注释、去空行后的前 1500 行和后 1500 行，共 3000 行、60 页。\n'
        '申请表中的著作权人、证件号码、开发完成日期和首次发表日期需申请人确认。\n',
        encoding='utf-8'
    )
    print(manual)
    print(code)
    print(info)
    print(manifest)


if __name__ == '__main__':
    main()



















