"""Builds docs/bpcGit-consultant-guide.pdf from the screenshots in docs/guide-images.

The screenshots come from the real UI with fictitious data: run
node tests/demo/server.cjs, then node tests/demo/capture.cjs docs/guide-images
(needs puppeteer-core and Chrome). Requires reportlab and Pillow.
Run: python tools/make_consultant_pdf.py
"""
import os

from PIL import Image as PilImage
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (Image, KeepTogether, PageBreak, Paragraph, Preformatted,
                                SimpleDocTemplate, Spacer, Table, TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, '..', 'docs')
IMAGES = os.path.join(DOCS, 'guide-images')
OUT = os.path.join(DOCS, 'bpcGit-consultant-guide.pdf')
WIDTH = 170 * mm

INK = colors.HexColor('#1f2933')
MUTED = colors.HexColor('#52606d')
ACCENT = colors.HexColor('#0b6e99')
ACCENT_LIGHT = colors.HexColor('#e6f3f8')
AMBER_LIGHT = colors.HexColor('#fdf3e1')
AMBER = colors.HexColor('#b26b00')
RULE = colors.HexColor('#d9e2ec')
CODE_BG = colors.HexColor('#f4f6f8')

S = {
    'title': ParagraphStyle('title', fontName='Helvetica-Bold', fontSize=28, leading=34,
                            textColor=ACCENT),
    'subtitle': ParagraphStyle('subtitle', fontName='Helvetica', fontSize=13, leading=18,
                               textColor=MUTED),
    'h1': ParagraphStyle('h1', fontName='Helvetica-Bold', fontSize=16, leading=21,
                         textColor=ACCENT, spaceBefore=10, spaceAfter=6),
    'h2': ParagraphStyle('h2', fontName='Helvetica-Bold', fontSize=11.5, leading=15,
                         textColor=INK, spaceBefore=6, spaceAfter=3),
    'body': ParagraphStyle('body', fontName='Helvetica', fontSize=10, leading=14.5,
                           textColor=INK, spaceAfter=5),
    'small': ParagraphStyle('small', fontName='Helvetica', fontSize=9, leading=12.5,
                            textColor=INK),
    'caption': ParagraphStyle('caption', fontName='Helvetica-Oblique', fontSize=8.5,
                              leading=11, textColor=MUTED, spaceBefore=3, spaceAfter=8),
    'code': ParagraphStyle('code', fontName='Courier', fontSize=8.5, leading=11.5,
                           textColor=INK),
}


def p(text, style='body'):
    return Paragraph(text, S[style])


def bullets(items):
    return [Paragraph(item, S['body'], bulletText='•') for item in items]


def box(flowables, background=ACCENT_LIGHT, border=ACCENT):
    t = Table([[flowables]], colWidths=[WIDTH])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), background),
        ('LINEBEFORE', (0, 0), (0, -1), 3, border),
        ('LEFTPADDING', (0, 0), (-1, -1), 10), ('RIGHTPADDING', (0, 0), (-1, -1), 10),
        ('TOPPADDING', (0, 0), (-1, -1), 8), ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
    ]))
    return t


def note(text):
    return box([p(text, 'small')], AMBER_LIGHT, AMBER)


def code(text):
    t = Table([[Preformatted(text, S['code'])]], colWidths=[WIDTH])
    t.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, -1), CODE_BG),
                           ('LEFTPADDING', (0, 0), (-1, -1), 8),
                           ('TOPPADDING', (0, 0), (-1, -1), 6),
                           ('BOTTOMPADDING', (0, 0), (-1, -1), 6)]))
    return t


def grid(rows, widths):
    data = [[p(c, 'small') for c in r] for r in rows]
    t = Table(data, colWidths=[w * mm for w in widths], repeatRows=1)
    t.setStyle(TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BACKGROUND', (0, 0), (-1, 0), ACCENT_LIGHT),
        ('LINEBELOW', (0, 0), (-1, -1), 0.5, RULE),
        ('LEFTPADDING', (0, 0), (-1, -1), 5), ('RIGHTPADDING', (0, 0), (-1, -1), 5),
        ('TOPPADDING', (0, 0), (-1, -1), 4), ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    return t


def shot(name, caption, width=WIDTH, max_height=150 * mm):
    path = os.path.join(IMAGES, name)
    w, h = PilImage.open(path).size
    draw_w = width
    draw_h = draw_w * h / w
    if draw_h > max_height:
        draw_h = max_height
        draw_w = draw_h * w / h
    img = Image(path, width=draw_w, height=draw_h)
    frame = Table([[img]], colWidths=[draw_w + 2])
    frame.setStyle(TableStyle([('BOX', (0, 0), (-1, -1), 0.6, RULE),
                               ('LEFTPADDING', (0, 0), (-1, -1), 0),
                               ('RIGHTPADDING', (0, 0), (-1, -1), 0),
                               ('TOPPADDING', (0, 0), (-1, -1), 0),
                               ('BOTTOMPADDING', (0, 0), (-1, -1), 0)]))
    return KeepTogether([frame, p(caption, 'caption')])


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont('Helvetica', 8)
    canvas.setFillColor(MUTED)
    canvas.drawString(20 * mm, 12 * mm, 'bpcGit - consultant guide')
    canvas.drawRightString(190 * mm, 12 * mm, 'Page %d' % doc.page)
    canvas.restoreState()


story = []

# 1. Introduction
story += [
    Spacer(1, 10 * mm),
    p('bpcGit', 'title'),
    p('Consultant guide: setup, daily use and transports', 'subtitle'),
    Spacer(1, 8 * mm),
    p('This guide is for BPC consultants and administrators who set up and use bpcGit on '
      'SAP BPC 10.1 (NetWeaver). It explains how the app works, where things are stored, and '
      'what each screen does. For a non-technical introduction, see the separate '
      '<i>bpcGit overview</i>.'),
    box([p('<b>Screenshots</b> show the real bpcGit screens with fictitious sample data '
           '(environment CORP_PLAN, models FINANCE and OPEX). Your environment, models and '
           'users will differ.', 'small')]),
    p('How it works', 'h1'),
    *bullets([
        '<b>Runs inside SAP.</b> bpcGit is a UI5 application (BSP <font face="Courier">ZBPC_GIT</font>) '
        'with an ABAP backend (HTTP handler <font face="Courier">ZCL_BPC_GIT_HTTP</font>). It is '
        'installed with abapGit into package <font face="Courier">ZBPC_GIT</font>.',
        '<b>Talks to Git through abapGit.</b> abapGit must be installed in the system. Git hosting '
        'can be GitHub or Bitbucket Cloud; Bitbucket adds faster history and diff reads and '
        'optional Git LFS for large workbooks.',
        '<b>Reads and writes BPC through BPC\'s own APIs</b>: the file service for documents, and '
        'the Data Manager, security, BPF and member APIs for the other objects.',
        '<b>One repository and branch per environment.</b> The setup is stored in table '
        '<font face="Courier">ZBPC_GIT_REPO</font>; the last synced version of each object is '
        'stored in <font face="Courier">ZBPC_GIT_STATE</font>.',
    ]),
    p('Opening the app', 'h2'),
    code('/sap/bc/ui5_ui5/sap/zbpc_git/index.html?sap-client=<client>'),
    Spacer(1, 4),
    p('Use this UI5 path rather than /sap/bc/bsp/sap/...: the BSP runtime rejects host names '
      'without a domain.'),
]

# 2. Repository setup
story += [
    PageBreak(),
    p('1. Repository setup', 'h1'),
    p('The Repository setup panel sits at the top of the page. When it is collapsed, its header '
      'still shows the saved repository and branch; <b>Change</b> opens the panel and puts the '
      'cursor in the Branch field.'),
    shot('00_header.png', 'The header shows the saved repository (without credentials) and '
         'branch.'),
    shot('01_setup.png', 'Repository setup for one BPC environment.', max_height=66 * mm),
    grid([
        ['Field', 'What to enter'],
        ['BPC environment', 'The environment this repository belongs to.'],
        ['Repository URL', 'HTTPS URL of the Git repository. Credentials can be included as '
         '<font face="Courier">user:token@host</font> (see below) or entered with Log in.'],
        ['BPC root folder', 'Folder inside the repository that holds the BPC content, for example '
         '<font face="Courier">bpc</font>. Leave empty to use the repository root.'],
        ['Branch', 'Opening the list loads the branches; you can also type a new branch name.'],
        ['Git LFS', 'Bitbucket Cloud only. EPM workbooks at or above the threshold (1-100 MB) are '
         'stored in LFS on their next commit.'],
    ], [38, 132]),
    Spacer(1, 6),
    p('Credentials', 'h2'),
    code('https://x-token-auth:YOUR_BITBUCKET_TOKEN@bitbucket.org/WORKSPACE/REPOSITORY.git\n'
         'https://YOUR_GITHUB_USERNAME:YOUR_GITHUB_PAT@github.com/OWNER/REPOSITORY.git'),
    Spacer(1, 4),
    *bullets([
        'Bitbucket repository access token: user <font face="Courier">x-token-auth</font>. '
        'Bitbucket API token: your Atlassian e-mail.',
        'GitHub fine-grained token: <b>Contents: Read-only</b> to read, <b>Read and write</b> '
        'to commit.',
        'A token in the URL is visible to every user who can open the environment\'s setup. '
        '<b>Log in</b> keeps credentials in the browser tab only.',
        'SAP must trust the Git host certificates (STRUST, with SNI). Bitbucket history and diff '
        'also need <font face="Courier">api.bitbucket.org</font>.',
    ]),
    p('<b>Test connection</b> checks read access and lists the branches; <b>Log in and check push '
      'access</b> confirms you can commit.'),
]

# 3. Repository layout
story += [
    PageBreak(),
    p('2. What is stored, and where', 'h1'),
    p('Every object becomes a file in the repository. Documents keep their BPC path below '
      '<font face="Courier">\\ROOT\\WEBFOLDERS\\&lt;ENV&gt;\\</font> (with / instead of \\); '
      'objects stored in tables are written as generated XML.'),
    grid([
        ['Object', 'Repository path'],
        ['EPM workbooks', '<font face="Courier">&lt;MODEL&gt;/EEXCEL/REPORTS/...xlsx</font>, '
         '<font face="Courier">.../INPUT SCHEDULES/...</font>, also below '
         '<font face="Courier">&lt;MODEL&gt;/TEAM FILES/&lt;TEAM&gt;/</font>'],
        ['Logic scripts', '<font face="Courier">ADMINAPP/&lt;MODEL&gt;/&lt;NAME&gt;.LGF</font> '
         '(compiled .LGX files are not tracked)'],
        ['Transformation files', '<font face="Courier">&lt;MODEL&gt;/DATAMANAGER/'
         'TRANSFORMATIONFILES/...TDM</font> plus its Excel workbook'],
        ['Conversion files', '<font face="Courier">&lt;MODEL&gt;/DATAMANAGER/CONVERSIONFILES/'
         '...CDM</font> plus its Excel workbook'],
        ['Data Manager packages', '<font face="Courier">&lt;MODEL&gt;/DATAMANAGER/PACKAGES/'
         '&lt;GROUP&gt;/&lt;PACKAGE&gt;.xml</font>'],
        ['Package links', '<font face="Courier">&lt;MODEL&gt;/DATAMANAGER/PACKAGELINKS/'
         '&lt;NAME&gt;.xml</font>'],
        ['Security', '<font face="Courier">SECURITY/TEAMS/</font>, '
         '<font face="Courier">SECURITY/TASKPROFILES/</font>, '
         '<font face="Courier">SECURITY/DATAACCESSPROFILES/</font>'],
        ['BPF templates', '<font face="Courier">&lt;MODEL&gt;/BPF/&lt;technical name&gt;.xml'
         '</font>'],
        ['Dimension members', '<font face="Courier">DIMENSIONS/&lt;DIM&gt;/MEMBERS/'
         '&lt;MEMBER&gt;.xml</font>'],
    ], [40, 130]),
    Spacer(1, 6),
    p('A transformation or conversion definition and its workbook are handled as a pair: they '
      'are committed, restored and transported together. BPC file names are upper case and kept '
      'as they are.'),
    note('Excel workbooks are binary. Git keeps every version, but Diff does not show cell '
         'changes: for workbooks it reports only that the file changed.'),
]

# 4. Overview
story += [
    PageBreak(),
    p('3. The overview: what has changed?', 'h1'),
    p('Pick an <b>Object type</b> and optionally a <b>Model</b>, then <b>Load</b>. bpcGit compares '
      'BPC with the branch and lists each object with its status. The banner shows the branch, '
      'the commit compared against, and a count per status.'),
    shot('02_scripts.png', 'Logic scripts of two models, with every common status.',
         max_height=125 * mm),
    grid([
        ['Status', 'Meaning', 'Typical action'],
        ['Unchanged', 'BPC matches the last synced Git version', 'None; History is available'],
        ['Modified in BPC', 'Changed in BPC since the last sync', 'Diff, then Commit'],
        ['New in BPC', 'Exists only in BPC', 'Commit'],
        ['Modified in Git', 'Someone committed a newer version', 'Restore'],
        ['New in Git', 'Exists only in Git', 'Restore'],
        ['Conflict', 'Changed in BPC and in Git', 'Decide which side wins'],
        ['Deleted in BPC / Git', 'Synced before, now missing on one side', 'Commit or Restore'],
        ['Differs, never synced', 'Different, but never synced through bpcGit', 'Commit (BPC wins) '
         'or Restore (Git wins)'],
    ], [38, 74, 58]),
    Spacer(1, 6),
    p('<b>Select BPC changes</b> and <b>Select Git changes</b> tick everything that can be '
      'committed or restored. The search box and the model, type and location filters help in '
      'large environments.'),
]

# 5. Diff and history
story += [
    PageBreak(),
    p('4. Diff: what exactly changed?', 'h1'),
    p('Select one logic script, transformation, conversion, package or package link and choose '
      '<b>Diff</b>. It compares the Git version with the current BPC version, line by line. '
      'Red lines with a minus are the Git version; green lines with a plus are what is in BPC now.'),
    shot('04_diff.png', 'CLEAR_FORECAST.LGF: a comment was added, the audit trail scope was '
         'widened and a filter for open periods was added in BPC.', max_height=115 * mm),
    p('5. History: who changed what, and when', 'h1'),
    p('Select an object and choose <b>History</b> to see every commit that changed it, newest '
      'first, with the author, date and commit message. Selecting a version and choosing '
      '<b>Restore selected version</b> puts that older version back into BPC, optionally recording '
      'it in a transport request.'),
    shot('05_history.png', 'History of a logic script with an older version selected.',
         width=130 * mm),
]

# 6. Commit and restore
story += [
    PageBreak(),
    p('6. Commit: save BPC changes to Git', 'h1'),
    p('Tick objects with a BPC-side change and choose <b>Commit</b>. The dialog lists what will '
      'happen to each object and asks for a message. All selected objects go into one commit, '
      'authored with your SAP user\'s name and e-mail.'),
    shot('06_commit.png', 'Committing an updated and a new logic script together.',
         width=120 * mm),
    *bullets([
        'Before writing, bpcGit checks that the branch has not moved since you loaded the list; '
        'if it has, reload and try again.',
        'Conflicts are never committed blindly: decide first whether BPC or Git wins.',
    ]),
    p('7. Restore: put a Git version back into BPC', 'h1'),
    p('Tick objects and choose <b>Restore</b>. The dialog states what will be overwritten, created '
      'or deleted in BPC. A transport request can be chosen in the same dialog.'),
    shot('07_restore.png', 'Restoring a newer Git version of a logic script.', width=120 * mm),
    note('bpcGit does not keep a copy of a BPC version that was never committed. Restoring '
         'over an uncommitted BPC change loses it. Files open for editing in BPC are skipped. '
         'Restoring dimension members processes the whole dimension, including other pending '
         'member edits.'),
]

# 7. Transports
story += [
    PageBreak(),
    p('8. Transport requests', 'h1'),
    p('bpcGit can put BPC objects into a <b>customizing transport request</b>, either with '
      '<b>Add to transport</b> (objects as they are in BPC now; nothing is restored) or while '
      'restoring. The request must be an open customizing request of the current client in which '
      'you have an open task; a new request can be created from the dialog on the default '
      'transport layer.'),
    shot('08_transport.png', 'Adding two logic scripts to an open customizing request.',
         width=80 * mm),
    p('How objects are recorded', 'h2'),
    p('bpcGit records objects exactly as BPC\'s own transport does, so release and import work '
      'as usual:'),
    *bullets([
        'Each object is identified by a BPC <i>entity</i>: environment, model, entity type and '
        'entity ID. Its GUID is read from table <font face="Courier">UJT_GUID</font>, or generated '
        'and stored there the first time. The same object always keeps the same GUID.',
        'The request gets an entry <font face="Courier">R3TR ABPC &lt;GUID&gt;</font> (or the entity '
        'type itself for types with their own transport object) in your task.',
        'BPC exports the content when the request is <b>released</b>, so later changes to the '
        'object before release are included.',
    ]),
    grid([
        ['Object', 'Entity type', 'Entity ID'],
        ['EPM workbook', 'AFLE', '<font face="Courier">COMPANY\\EEXCEL\\...</font> or '
         '<font face="Courier">&lt;team&gt;\\EEXCEL\\...</font>'],
        ['Transformation / conversion', 'ADMF', '<font face="Courier">COMPANY\\DATAMANAGER\\'
         '&lt;folder&gt;\\&lt;name&gt;</font> (no extension)'],
        ['Logic script', 'ASPR', '<font face="Courier">ADMINAPP\\&lt;MODEL&gt;\\&lt;NAME&gt;.LGF'
         '</font>'],
        ['Data Manager package', 'ADMP', 'team, group and package ID'],
        ['Package link', 'ADML', 'link name'],
        ['Dimension members', 'AMBR', 'dimension (all members of the dimension)'],
        ['BPF template', 'ABPF', 'template GUID'],
        ['Team / task profile / data access profile', 'ATEM / ATPF / ADAF', 'ID'],
    ], [52, 34, 84]),
    Spacer(1, 6),
    note('To see what a GUID stands for, look it up in <font face="Courier">UJT_GUID</font> '
         '(SE16, field GUID); <font face="Courier">E071</font> shows which requests contain it. '
         'Deletions are not transported. An object that is already in the request or in one of '
         'its open tasks is not added twice; entries of released tasks are not counted.'),
]

# 8. Workflows and limits
story += [
    PageBreak(),
    p('9. Recommended ways of working', 'h1'),
    p('First baseline', 'h2'),
    p('After setup, load <b>All objects</b>, select the BPC changes and commit them with a message '
      'such as "Baseline of CORP_PLAN". From then on, every change shows up as a status.'),
    p('A change from development to production', 'h2'),
    grid([
        ['Step', 'In bpcGit'],
        ['1. Change', 'Edit the script, report or package in the development system.'],
        ['2. Review', 'Load the object type; check the change with Diff.'],
        ['3. Commit', 'Commit with a message that explains why, and a ticket number if you '
         'have one.'],
        ['4. Transport', 'Add to transport, then release the request as usual.'],
        ['5. Recover', 'If something breaks, use History and Restore selected version.'],
    ], [28, 142]),
    Spacer(1, 6),
    p('Good habits', 'h2'),
    *bullets([
        'Commit small, related changes together and write messages for the next consultant.',
        'Load and review statuses before a restore: Modified in BPC means someone has work that '
        'is not committed yet.',
        'Use branches for parallel work, for example a release branch per go-live.',
    ]),
    p('10. Limits to know', 'h1'),
    *bullets([
        'Targets SAP BPC 10.1 NW on ABAP 7.52 or later with UI5 1.52; abapGit must be installed.',
        'Workbook diffs show that a file changed, not which cells changed.',
        'Git LFS is supported for Bitbucket Cloud only (up to 128 MB per file).',
        'Deletions are not recorded in transport requests.',
        'Restoring a package over a custom script requires resetting the package to its default '
        'script in BPC first; scheduled package links cannot be deleted.',
    ]),
]

doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm,
                        topMargin=18 * mm, bottomMargin=20 * mm,
                        title='bpcGit - consultant guide', author='bpcGit')
doc.build(story, onFirstPage=footer, onLaterPages=footer)
print(os.path.abspath(OUT))
