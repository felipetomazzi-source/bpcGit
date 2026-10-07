"""Builds docs/bpcGit-overview.pdf, a plain-language introduction to bpcGit.

Requires reportlab (pip install reportlab). Run: python tools/make_overview_pdf.py
"""
import os

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (KeepTogether, PageBreak, Paragraph, SimpleDocTemplate,
                                Spacer, Table, TableStyle)

OUT = os.path.join(os.path.dirname(__file__), '..', 'docs', 'bpcGit-overview.pdf')

INK = colors.HexColor('#1f2933')
MUTED = colors.HexColor('#52606d')
ACCENT = colors.HexColor('#0b6e99')
ACCENT_LIGHT = colors.HexColor('#e6f3f8')
GREEN_LIGHT = colors.HexColor('#e8f5ec')
GREEN = colors.HexColor('#1e7b45')
RULE = colors.HexColor('#d9e2ec')

base = dict(fontName='Helvetica', textColor=INK, alignment=TA_LEFT)
S = {
    'title': ParagraphStyle('title', fontName='Helvetica-Bold', fontSize=30, leading=36,
                            textColor=ACCENT),
    'subtitle': ParagraphStyle('subtitle', fontName='Helvetica', fontSize=14, leading=19,
                               textColor=MUTED),
    'h1': ParagraphStyle('h1', fontName='Helvetica-Bold', fontSize=17, leading=22,
                         textColor=ACCENT, spaceBefore=14, spaceAfter=6),
    'h2': ParagraphStyle('h2', fontName='Helvetica-Bold', fontSize=11.5, leading=15,
                         textColor=INK, spaceAfter=2),
    'body': ParagraphStyle('body', fontSize=10.5, leading=15, spaceAfter=6, **base),
    'small': ParagraphStyle('small', fontSize=9.5, leading=13, **base),
    'muted': ParagraphStyle('muted', fontSize=9, leading=12, textColor=MUTED,
                            fontName='Helvetica'),
    'callout': ParagraphStyle('callout', fontSize=11, leading=16, **base),
}


def p(text, style='body'):
    return Paragraph(text, S[style])


def box(flowables, background, border):
    t = Table([[flowables]], colWidths=[170 * mm])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), background),
        ('LINEBEFORE', (0, 0), (0, -1), 3, border),
        ('LEFTPADDING', (0, 0), (-1, -1), 12),
        ('RIGHTPADDING', (0, 0), (-1, -1), 12),
        ('TOPPADDING', (0, 0), (-1, -1), 10),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 10),
    ]))
    return t


def grid(rows, widths, header=True):
    data = [[p(c, 'small') if not isinstance(c, Paragraph) else c for c in r] for r in rows]
    t = Table(data, colWidths=[w * mm for w in widths], repeatRows=1 if header else 0)
    style = [
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LINEBELOW', (0, 0), (-1, -1), 0.5, RULE),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]
    if header:
        style += [('BACKGROUND', (0, 0), (-1, 0), ACCENT_LIGHT)]
    t.setStyle(TableStyle(style))
    return t


def feature(title, text):
    return KeepTogether([p(title, 'h2'), p(text), Spacer(1, 2)])


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont('Helvetica', 8)
    canvas.setFillColor(MUTED)
    canvas.drawString(20 * mm, 12 * mm, 'bpcGit - version control for SAP BPC')
    canvas.drawRightString(190 * mm, 12 * mm, 'Page %d' % doc.page)
    canvas.restoreState()


story = []

# Cover / introduction
story += [
    Spacer(1, 18 * mm),
    p('bpcGit', 'title'),
    Spacer(1, 4),
    p('A safety net and a history book for your SAP BPC content', 'subtitle'),
    Spacer(1, 12 * mm),
    box([p('<b>In one sentence:</b> bpcGit keeps every saved version of your BPC '
           'reports, input schedules, logic scripts, Data Manager files, security '
           'and BPF designs, so you can see what changed, who changed it, and put '
           'back any earlier version with a few clicks.', 'callout')],
        ACCENT_LIGHT, ACCENT),
    Spacer(1, 8 * mm),
    p('Something BPC has never had', 'h1'),
    p('Standard SAP BPC (NetWeaver) has no version history for its content. When '
      'someone saves a logic script, a report or a transformation file, the previous '
      'version is simply gone, unless somebody remembered to keep a copy by hand. '
      'Finding out what changed, or undoing a change that broke month-end, usually '
      'means detective work.'),
    p('bpcGit brings proper version control to BPC, a capability BPC has never '
      'offered out of the box. It runs inside your SAP system, in the browser, and '
      'it is built for BPC people: you do not need to know Git or GitHub to use it.'),
    Spacer(1, 4 * mm),
    box([p('<b>No Git knowledge needed.</b> You work in a normal BPC-style screen with '
           'buttons such as <i>Commit</i>, <i>History</i>, <i>Diff</i> and '
           '<i>Restore</i>. bpcGit does the Git work behind the scenes.', 'callout')],
        GREEN_LIGHT, GREEN),
]

# Git in plain words
story += [
    PageBreak(),
    p('Git in plain words', 'h1'),
    p('Git is the tool software teams around the world use to keep the history of '
      'their work. GitHub and Bitbucket are websites that store that history safely. '
      'You only need a handful of words:'),
    grid([
        ['Word', 'What it means for you'],
        ['<b>Repository</b>', 'The place where the history is kept, like a shared '
         'archive folder that never forgets. It lives on GitHub or Bitbucket.'],
        ['<b>Commit</b>', 'Saving a snapshot of selected objects into the archive, '
         'with a short note such as "Fix FX rate in CLEAR_DATA script". Your name '
         'and the date are recorded automatically.'],
        ['<b>History</b>', 'The list of all snapshots of an object: who, when and why.'],
        ['<b>Diff</b>', 'A line-by-line comparison showing what is different '
         'between the saved version and BPC.'],
        ['<b>Restore</b>', 'Putting a version from the archive back into BPC.'],
        ['<b>Branch</b>', 'A separate line of work in the same archive, for example '
         'one for development and one for production.'],
    ], [35, 135]),
    Spacer(1, 6 * mm),
    p('A simple way to think about it', 'h2'),
    p('Think of the <i>Track changes</i> and <i>Version history</i> features of Word '
      'or SharePoint, but for everything in a BPC environment, and with a note on '
      'every change explaining why it was made.'),
    Spacer(1, 4 * mm),
    p('What bpcGit looks after', 'h1'),
    grid([
        ['Content', 'Examples'],
        ['EPM workbooks', 'Reports and input schedules, company and team folders'],
        ['Logic scripts', 'Script logic files (.LGF) of every model'],
        ['Data Manager', 'Transformation and conversion files, packages and '
         'package links'],
        ['Security', 'Teams, task profiles and data access profiles'],
        ['Business process flows', 'BPF template designs'],
        ['Dimension members', 'Members and their properties, per dimension'],
    ], [45, 125]),
]

# Features
story += [
    PageBreak(),
    p('What you can do', 'h1'),
    feature('1. See where everything stands',
            'Choose an object type and a model, then <b>Load</b>. Every object gets a '
            'clear status, such as <i>Unchanged</i>, <i>Modified in BPC</i>, '
            '<i>New in BPC</i> or <i>Modified in Git</i>, so you can see at a glance '
            'what has changed since the last snapshot. Filters and a search box help '
            'in large environments.'),
    feature('2. Save a version (Commit)',
            'Tick the objects you changed and choose <b>Commit</b>. Write a short note '
            'about the change. bpcGit saves all selected objects together as one '
            'snapshot, signed with your SAP user name.'),
    feature('3. See the history',
            'Select an object and choose <b>History</b> to see every saved version: '
            'who saved it, when, and the note they wrote.'),
    feature('4. See exactly what changed (Diff)',
            'For logic scripts, transformation and conversion files, Data Manager '
            'packages and package links, <b>Diff</b> compares the saved version with '
            'what is in BPC now, line by line: lines that were removed are shown in '
            'red, lines that were added in green.'),
    feature('5. Undo mistakes (Restore)',
            'Put the saved version back into BPC, or go back to any older version '
            'from the history. bpcGit always shows what will be overwritten before '
            'anything happens, and files that are open for editing in BPC are left '
            'alone.'),
    feature('6. Move changes with transport requests',
            'Add the selected objects to a customizing transport request with '
            '<b>Add to transport</b>, or record them automatically while restoring. '
            'bpcGit records them exactly the way BPC\'s own transport does, so the '
            'normal release and import process to quality and production systems '
            'works unchanged.'),
    feature('7. Large workbooks',
            'Very large Excel workbooks can be stored with Git LFS (Bitbucket), which '
            'keeps the repository fast while every version stays available.'),
    feature('8. Nothing to install on your PC',
            'bpcGit is a web application inside SAP. It works with GitHub and '
            'Bitbucket, and uses your normal SAP login.'),
]

# Benefits
story += [
    PageBreak(),
    p('Why it matters', 'h1'),
    grid([
        ['Benefit', 'What it means in practice'],
        ['<b>A safety net</b>', 'A broken script or report can be put back to its '
         'last good version in minutes, even during close.'],
        ['<b>A clear audit trail</b>', 'Every change has a name, a date and a reason. '
         'Useful for auditors, for SOX-style controls and for anyone taking over '
         'the system.'],
        ['<b>Fewer surprises</b>', 'Before you restore or move anything, you can see '
         'exactly what is different.'],
        ['<b>Better teamwork</b>', 'Consultants, administrators and business users '
         'work from the same history instead of private copies and e-mail '
         'attachments.'],
        ['<b>Safer moves to production</b>', 'Changes go through the normal SAP '
         'transport process, and the repository shows what each one contains.'],
        ['<b>Knowledge that stays</b>', 'The notes on every commit explain why the '
         'system looks the way it does, long after the people who built it have '
         'moved on.'],
        ['<b>Disaster recovery</b>', 'A copy of all BPC content lives outside SAP, on '
         'GitHub or Bitbucket.'],
    ], [48, 122]),
    Spacer(1, 8 * mm),
    p('A typical change, step by step', 'h1'),
    grid([
        ['Step', 'What happens'],
        ['1', 'An administrator updates the logic script that clears forecast data.'],
        ['2', 'In bpcGit the script shows <i>Modified in BPC</i>. <b>Diff</b> confirms '
         'that only the intended lines changed.'],
        ['3', 'They <b>Commit</b> it with the note "Clear forecast only for open '
         'periods".'],
        ['4', 'They choose <b>Add to transport</b> and pick a customizing request, '
         'which is then released to production as usual.'],
        ['5', 'If anything goes wrong, <b>History</b> and <b>Restore</b> put the '
         'previous version back in a few clicks.'],
    ], [14, 156]),
    Spacer(1, 10 * mm),
    box([p('<b>The bottom line:</b> bpcGit gives SAP BPC what modern software teams '
           'take for granted: a complete, searchable history of every change, and '
           'the confidence to change things because you can always go back.',
           'callout')],
        ACCENT_LIGHT, ACCENT),
]

doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm,
                        topMargin=20 * mm, bottomMargin=20 * mm,
                        title='bpcGit - version control for SAP BPC',
                        author='bpcGit')
doc.build(story, onFirstPage=footer, onLaterPages=footer)
print(os.path.abspath(OUT))
