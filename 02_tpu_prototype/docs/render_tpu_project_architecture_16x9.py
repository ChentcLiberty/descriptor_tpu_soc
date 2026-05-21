from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
BG = "#f8f6f1"
TEXT = "#243241"
BORDER = "#435465"

FONT_PATH = "/usr/share/fonts/wqy-zenhei/wqy-zenhei.ttc"
OUT_PATH = Path("/home/jjt/tpu-soc/docs/tpu_project_architecture_16x9_zh.png")

TITLE_FONT = ImageFont.truetype(FONT_PATH, 42)
SUB_FONT = ImageFont.truetype(FONT_PATH, 22)
CLUSTER_FONT = ImageFont.truetype(FONT_PATH, 22)
BOX_FONT = ImageFont.truetype(FONT_PATH, 24)
SMALL_FONT = ImageFont.truetype(FONT_PATH, 18)
TAG_FONT = ImageFont.truetype(FONT_PATH, 18)

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)


def rr(rect, fill, outline=BORDER, width=3, radius=22):
    draw.rounded_rectangle(rect, radius=radius, fill=fill, outline=outline, width=width)


def centered_text(rect, text, font, fill=TEXT, spacing=6):
    x1, y1, x2, y2 = rect
    bbox = draw.multiline_textbbox((0, 0), text, font=font, spacing=spacing, align="center")
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = x1 + (x2 - x1 - tw) / 2
    y = y1 + (y2 - y1 - th) / 2 - 2
    draw.multiline_text((x, y), text, font=font, fill=fill, spacing=spacing, align="center")


def label_text(x, y, text, font, fill=TEXT):
    draw.text((x, y), text, font=font, fill=fill)


def box(rect, text, fill, outline=BORDER, width=3, radius=22, font=BOX_FONT):
    rr(rect, fill=fill, outline=outline, width=width, radius=radius)
    centered_text(rect, text, font)


def arrow(p1, p2, color, width=4, head=12):
    x1, y1 = p1
    x2, y2 = p2
    draw.line([p1, p2], fill=color, width=width)
    if x1 == x2:
        direction = 1 if y2 > y1 else -1
        pts = [(x2, y2), (x2 - head, y2 - direction * head), (x2 + head, y2 - direction * head)]
    else:
        direction = 1 if x2 > x1 else -1
        pts = [(x2, y2), (x2 - direction * head, y2 - head), (x2 - direction * head, y2 + head)]
    draw.polygon(pts, fill=color)


def poly_arrow(points, color, width=4, head=12):
    for a, b in zip(points, points[1:]):
        draw.line([a, b], fill=color, width=width)
    arrow(points[-2], points[-1], color, width=width, head=head)


def dashed_poly(points, color, width=3, dash=12, gap=8, head=11):
    for a, b in zip(points, points[1:]):
        if a[0] == b[0]:
            x = a[0]
            y1, y2 = sorted([a[1], b[1]])
            cur = y1
            while cur < y2:
                nxt = min(cur + dash, y2)
                draw.line([(x, cur), (x, nxt)], fill=color, width=width)
                cur = nxt + gap
        else:
            y = a[1]
            x1, x2 = sorted([a[0], b[0]])
            cur = x1
            while cur < x2:
                nxt = min(cur + dash, x2)
                draw.line([(cur, y), (nxt, y)], fill=color, width=width)
                cur = nxt + gap
    arrow(points[-2], points[-1], color, width=width, head=head)


def arrow_label(pos, text, color):
    rr((pos[0] - 40, pos[1] - 15, pos[0] + 40, pos[1] + 15), fill=BG, outline=BG, width=0, radius=10)
    centered_text((pos[0] - 40, pos[1] - 15, pos[0] + 40, pos[1] + 15), text, TAG_FONT, fill=color, spacing=2)


# Header
box((40, 32, 840, 108), "TinyTPU AXI-Lite SoC 整体架构图", "#efe4cf", outline="#8b6b3f", width=4, radius=24, font=TITLE_FONT)
box((870, 40, 1480, 102), "系统集成 + 指令化执行 + 验证闭环", "#f5efe3", outline="#b38c54", width=2, radius=18, font=SUB_FONT)
box((1510, 40, 1860, 102), "当前边界：无 DMA / IRQ", "#f1f5f9", outline="#7b8794", width=2, radius=18, font=SUB_FONT)

# Cluster regions
clusters = {
    "sw": ((40, 150, 430, 1010), "1. 软件与驱动", "#fff4df", "#c58a23"),
    "soc": ((470, 150, 900, 1010), "2. SoC 控制与执行", "#eaf2fd", "#2b6cb0"),
    "core": ((940, 150, 1370, 1010), "3. 计算核心", "#e7f6f1", "#0f766e"),
    "ver": ((1410, 150, 1880, 1010), "4. 验证与结果", "#f2ebff", "#7c3aed"),
}
for rect, label, fill, outline in clusters.values():
    rr(rect, fill=fill, outline=outline, width=3, radius=26)
    label_text(rect[0] + 18, rect[1] + 14, label, CLUSTER_FONT, fill=TEXT)

# Boxes
spec = (75, 215, 395, 315)
sched = (75, 345, 395, 455)
artifact = (75, 485, 395, 575)
cocotb = (75, 605, 395, 735)
vcs = (75, 770, 395, 880)

host = (520, 215, 850, 300)
axil = (520, 330, 850, 445)
imem = (520, 475, 850, 565)
seq = (520, 595, 850, 700)
soc = (520, 730, 850, 825)

ub = (990, 215, 1320, 325)
sysa = (990, 355, 1320, 445)
vpu = (990, 475, 1320, 585)
upd = (990, 615, 1320, 715)
obs = (990, 755, 1320, 845)

e2e = (1460, 215, 1835, 340)
train = (1460, 380, 1835, 485)
metrics = (1460, 525, 1835, 685)
scope = (1460, 730, 1835, 840)

box(spec, "模型规格\n2-layer MLP / XOR\nQ8.8 定点", "#fffdfa")
box(sched, "调度与编码\nscheduler.py\nencode_instrs.py", "#f3efe4")
box(artifact, "编译产物\nschedule.json\nimem.hex", "#fffdfa")
box(cocotb, "cocotb + NumPy\nAXI 驱动 / scoreboard\nQ8.8 参考模型", "#fffdfa")
box(vcs, "directed bench\n波形 / 定向 debug\nH1 问题复现", "#fffdfa")

box(host, "Host / PS\nAXI-Lite MMIO", "#f7e7d0")
box(axil, "tpu_frontend_axil\n寄存器堆 / CSR\nstart / status", "#fffdfa")
box(imem, "IMEM\n59 条 32-bit 指令", "#fffdfa")
box(seq, "Sequencer\nDISPATCH / WAIT\nADVANCE", "#fffdfa")
box(soc, "tpu_soc\nfrontend + TPU core", "#fffdfa")

box(ub, "Unified Buffer\nhost write / 读指针\nwriteback / update", "#fffdfa")
box(sysa, "Systolic Array\n2x2 Weight Stationary", "#fffdfa")
box(vpu, "VPU 算子链\nbias / 激活 / loss / grad", "#fffdfa")
box(upd, "参数更新路径\ngradient_descent\n回写 UB", "#fffdfa")
box(obs, "可观测点\nH1 / dZ2 / dZ1\nUB update", "#fffdfa")

box(e2e, "AXI e2e\n41 / 41 PASS\n覆盖 H1 + dZ2 + dZ1 + UB update", "#fffdfa")
box(train, "多 epoch 收敛\n12 epoch\nloss 0.2529 -> 0.1777", "#fffdfa")
box(metrics, "当前可讲结果\nXOR 预测 (0, 1, 1, 0)\n行为闭环已收敛\nFmax 164.10 -> 183.91 MHz", "#fffdfa")
box(scope, "边界说明\n当前 tiny-tpu 原型\n不是通用编译器 / 完整 SoC", "#fffdfa")

# Colors
orange = "#8b5e1a"
blue = "#2563eb"
red = "#c2410c"
green = "#0f766e"
purple = "#7c3aed"

# Software arrows
arrow((235, 315), (235, 345), orange)
arrow_label((300, 330), "模型到 schedule", orange)
arrow((235, 455), (235, 485), orange)
arrow_label((290, 470), "编码", orange)
poly_arrow([(395, 530), (455, 530), (455, 520), (520, 520)], orange)
arrow_label((456, 506), "装载指令", orange)
poly_arrow([(395, 670), (455, 670), (455, 258), (520, 258)], orange)
arrow_label((453, 448), "AXI 驱动", orange)
dashed_poly([(395, 825), (455, 825), (455, 778), (520, 778)], orange)
arrow_label((453, 808), "定向 debug", orange)

# SoC arrows
arrow((685, 300), (685, 330), blue)
arrow_label((740, 316), "MMIO", blue)
poly_arrow([(850, 388), (905, 388), (905, 520), (850, 520)], blue)
arrow_label((903, 456), "写 IMEM", blue)
arrow((685, 445), (685, 595), blue)
arrow_label((746, 520), "start / status", blue)
arrow((685, 565), (685, 595), blue)
arrow_label((760, 582), "wait_after", blue)
arrow((685, 700), (685, 730), blue)
arrow_label((766, 715), "seq_instr_pulse", blue)
poly_arrow([(850, 388), (920, 388), (920, 778), (850, 778)], red)
arrow_label((920, 580), "参数 / UB_DATA", red)

# Core arrows
arrow((850, 778), (990, 270), green)
arrow_label((918, 520), "数据搬运", green)
arrow((1155, 325), (1155, 355), green)
arrow_label((1222, 342), "矩阵块", green)
arrow((1155, 445), (1155, 475), green)
arrow_label((1238, 462), "中间结果", green)
arrow((1155, 585), (1155, 615), green)
arrow_label((1248, 602), "梯度 / 更新值", green)
poly_arrow([(1040, 615), (950, 615), (950, 270), (990, 270)], red)
arrow_label((945, 440), "回写 UB", red)
poly_arrow([(850, 778), (920, 778), (920, 800), (990, 800)], green)
arrow_label((920, 790), "对外观测", green)

# Verification arrows
arrow((1320, 800), (1460, 278), purple)
arrow_label((1388, 560), "scoreboard", purple)
dashed_poly([(395, 670), (1415, 670), (1415, 278), (1460, 278)], purple)
dashed_poly([(1650, 340), (1650, 380)], purple)
arrow_label((1716, 360), "行为正确", purple)
arrow((1648, 485), (1648, 525), purple)
dashed_poly([(1320, 400), (1388, 400), (1388, 605), (1460, 605)], purple)
arrow_label((1387, 500), "实现亮点", purple)

# Footer hint
footer = (70, 945, 1335, 1010)
rr(footer, fill="#f6f1e8", outline="#e4d6be", width=2, radius=18)
centered_text(footer, "5 页 PPT 足够：P1 项目定义  P2 整体架构  P3 控制/指令链路  P4 实现细节与关键 bug  P5 验证结果与边界", SUB_FONT, fill="#6b5a45", spacing=4)

OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT_PATH)
print(OUT_PATH)
