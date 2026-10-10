# 5. Typing and editing lines

Everything you type at the `>` prompt, and every answer to an `INPUT` in a
program, goes through a **line editor**. U64 BBC BASIC has two:

| Editor | Switch on with | In short |
|---|---|---|
| **BBC** (the default) | `*EDIT BBC` | Lines up to 238 characters, edited in place, earlier lines on the cursor keys, BBC Micro copy editing. Works the same in every screen mode. |
| **C64** | `*EDIT C64` | The C64's own full-screen editor: move the cursor anywhere on the screen and press RETURN to enter that line. Lines up to 78 characters after the prompt. |

`*EDIT` on its own tells you which one is in use. The choice holds until the
machine is restarted. Then it is BBC again.

## 5.1 The keys at a glance (BBC editor)

The C64 has two cursor keys: <kbd>CRSR ⇅</kbd> and <kbd>CRSR ⇄</kbd>. With
<kbd>SHIFT</kbd> they go the other way (up and left).

| Key on the C64 | What it does |
|---|---|
| letters, digits, signs | typed at the cursor; the rest of the line moves right |
| <kbd>CRSR ⇄</kbd> / <kbd>SHIFT</kbd>+<kbd>CRSR ⇄</kbd> | cursor right / left in the line |
| <kbd>CLR/HOME</kbd> | to the start of the line |
| <kbd>SHIFT</kbd>+<kbd>CLR/HOME</kbd> | to the end of the line |
| <kbd>INST/DEL</kbd> | delete the character left of the cursor |
| <kbd>SHIFT</kbd>+<kbd>INST/DEL</kbd> (INST) | insert a space at the cursor |
| <kbd>SHIFT</kbd>+<kbd>CRSR ⇅</kbd> (up) | the line you entered before (history) |
| <kbd>CRSR ⇅</kbd> (down) | back towards the newest line, then the line you were typing |
| <kbd>CTRL</kbd>+<kbd>CRSR ⇄</kbd> / <kbd>CTRL</kbd>+<kbd>SHIFT</kbd>+<kbd>CRSR ⇄</kbd> | copy cursor right / left |
| <kbd>CTRL</kbd>+<kbd>CRSR ⇅</kbd> / <kbd>CTRL</kbd>+<kbd>SHIFT</kbd>+<kbd>CRSR ⇅</kbd> | copy cursor down / up |
| <kbd>F1</kbd> | COPY: the character under the copy cursor |
| <kbd>RETURN</kbd> | enter the whole line, wherever the cursor is in it |
| <kbd>RUN/STOP</kbd> | ESCAPE: forget the line |

Letters type as capitals, as with CAPS LOCK on a BBC Micro. Hold
<kbd>SHIFT</kbd> for lower case. The ASCII signs the C64 keyboard does not
have are listed under `*HELP KEYBOARD`, for example `\` on the pound key and
`_` on the left-arrow key.

## 5.2 Typing a line

Type, and press <kbd>RETURN</kbd>:

```
>PRINT "Hello"
Hello
>
```

A line longer than the screen is wide simply continues on the next row.
At the prompt you can type up to 238 characters, as on a BBC Micro; at
the limit the machine beeps and takes no more.

A line with a number in front goes into the program instead of being run
at once:

```
>10 PRINT "Hello"
>20 GOTO 10
```

Typing a line number that already exists replaces that line. Typing only
the number deletes it.

## 5.3 Correcting while you type

You do not have to delete back to a mistake. Move to it:

1. Type `PRINT 1+3`.
2. You meant `12+3`. Press <kbd>SHIFT</kbd>+<kbd>CRSR ⇄</kbd> twice: the
   cursor is now on the `+`.
3. Type `2`. The line reads `PRINT 12+3`; the rest moved right.
4. Press <kbd>RETURN</kbd>. The cursor does not need to be at the end.

```
>PRINT 12+3
        15
```

To remove characters, put the cursor just after them and press
<kbd>INST/DEL</kbd>. <kbd>CLR/HOME</kbd> and <kbd>SHIFT</kbd>+<kbd>CLR/HOME</kbd>
jump to the start and the end of the line.

## 5.4 Earlier lines (history)

Every line you enter at the `>` prompt is remembered: the last 127 of them.

- <kbd>SHIFT</kbd>+<kbd>CRSR ⇅</kbd> (up) replaces the line you are typing
  with the previous one. Press again to go further back.
- <kbd>CRSR ⇅</kbd> (down) goes forward again. One step past the newest
  line you get back what you were typing before you started going back.
- The line that appears can be edited like any other before you press
  <kbd>RETURN</kbd>.

Not remembered: empty lines, a line that is the same as the one before it,
and answers to `INPUT` in programs. In an `INPUT` you can still fetch lines
from the history.

The history is kept in the REU (bank 0, `$8000-$FFFF`, see
[Memory](12_MEMORY.md)). It survives a cartridge restart and is lost when
the machine is switched off. Without an REU there is no history; the rest of
the editor works as described.

## 5.5 Editing a listed program line: copy editing

This is the BBC Micro way to change a line that is on the screen, for
example after `LIST`. You build a new line by copying characters from the
old one with a second cursor, the **copy cursor**, and type your changes in
between.

Say the program has a mistake in line 30:

```
>LIST
   10 FOR I%=1 TO 10
   20 PRINT I%*I%
   30 NEXT J%
>
```

The cursor is on the empty prompt line. To make line 30 read `NEXT I%`:

1. Hold <kbd>CTRL</kbd> and press <kbd>SHIFT</kbd>+<kbd>CRSR ⇅</kbd> once.
   A second cursor appears one row up, on the line `30 NEXT J%`, in the
   column where your cursor was. It is shown as an inverted character.
2. Still with <kbd>CTRL</kbd>, press <kbd>CRSR ⇄</kbd> twice: the copy cursor
   is now on the `3` of `30`.
3. Press <kbd>F1</kbd> (COPY) once for each character to copy (or hold it:
   it repeats). `30 NEXT `
   is eight presses (the leading spaces of the listing need not be copied:
   BASIC ignores them). Each press copies the character under the copy
   cursor into your line and moves the copy cursor one step right.
4. The copy cursor is now on the `J`. Do not copy it. Type `I` instead;
   the copy cursor stays where it is.
5. Skip the `J` in the old line: <kbd>CTRL</kbd>+<kbd>CRSR ⇄</kbd> once.
6. Press <kbd>F1</kbd> once more for the `%`.
7. Press <kbd>RETURN</kbd>. Your new line `30 NEXT I%` replaces the old line
   30, and the copy cursor disappears.

With `LISTO` switched on, the listing has extra spaces (after the line
number and in front of indented lines). Copy them along: BASIC does not mind
spaces there, it only takes more presses of <kbd>F1</kbd>.

The rules, in short:

- **Copy** with <kbd>F1</kbd>.
- **Change** by typing. Typing adds to your line and leaves the copy cursor
  alone.
- **Leave out** by moving the copy cursor past it with
  <kbd>CTRL</kbd>+cursor keys.
- **Insert** extra text by typing it before you copy on.

You can copy from anywhere on the screen, and from several places into one
line. Copying works on the text screen (`MODE 100`, `MODE 6` with the VIC-II)
and in teletext `MODE 7`. The graphics modes keep only pixels, not
characters, so there <kbd>F1</kbd> copies nothing.

For a line you typed recently, the history is quicker: press
<kbd>SHIFT</kbd>+<kbd>CRSR ⇅</kbd> until it appears, correct it, press
<kbd>RETURN</kbd>.

## 5.6 BASIC's own editing commands

| Command | What it does |
|---|---|
| `LIST`, `LIST 100,200` | show the program, or part of it |
| `*LIST` | the program indented by its structure, keywords spelt out |
| `LISTO 7` | `LIST` indents loops from now on |
| `AUTO`, `AUTO 100,5` | line numbers typed for you (ESCAPE stops) |
| `DELETE 100,200` | delete a range of lines |
| `RENUMBER`, `RENUMBER 1000,10` | number the lines again, GOTOs and GOSUBs follow |
| `NEW`, `OLD` | clear the program; bring it back after an accidental `NEW` |

See [BASIC keywords](06_BASIC.md) for the details.

## 5.7 Screen modes

The BBC editor works the same in every mode. In the graphics modes and in
`MODE 7` it uses the mode's own text cursor and text window (`VDU 28`): a
long line wraps at the window's right edge.

## 5.8 The C64 editor (`*EDIT C64`)

In the C64 text screen, `*EDIT C64` gives you the editor of the C64 itself:

- Move the cursor anywhere on the screen with the cursor keys, change what
  is there, and press <kbd>RETURN</kbd>: the whole screen line under the
  cursor is entered. That is how a listed line is edited.
- <kbd>INST/DEL</kbd>, <kbd>SHIFT</kbd>+<kbd>INST/DEL</kbd> and
  <kbd>CLR/HOME</kbd> work as on a C64; <kbd>SHIFT</kbd>+<kbd>CLR/HOME</kbd>
  clears the screen.
- A line can be 78 characters long after the `>` prompt (two screen rows).
- No history, no copy cursor.

In the graphics modes and in `MODE 7`, `*EDIT C64` means typing without
editing: characters, <kbd>INST/DEL</kbd> for the last one, <kbd>RETURN</kbd>.

`*EDIT BBC` switches back.

## 5.9 Good to know

- **ESCAPE** (<kbd>RUN/STOP</kbd>) while typing forgets the line: BASIC
  answers `Escape` and gives a fresh prompt. <kbd>RESTORE</kbd> does the
  same.
- **Function keys**: <kbd>F1</kbd> is COPY. The other function keys type
  nothing yet (`*KEY` is not there yet).
- **Key repeat**: the cursor keys, space and <kbd>INST/DEL</kbd> repeat while
  held; CTRL with a cursor key and <kbd>F1</kbd> (COPY) do too, after the
  same short delay: hold <kbd>F1</kbd> to copy the rest of a line.
- **From a PC** (VS Code, `tools/u64remote.py`, the MCP server; see
  [Developing from a PC](14_REMOTE.md)): a line sent from the PC wins. A
  half-typed line on the machine is dropped from the screen, and the PC's
  line is run.
- `GET` and `INKEY` in your own programs see the cursor keys as 136-139
  (left, right, down, up), <kbd>INST/DEL</kbd> as 127,
  <kbd>CLR/HOME</kbd> as 30 and <kbd>SHIFT</kbd>+<kbd>CLR/HOME</kbd> as 12. The editor is not involved there.
