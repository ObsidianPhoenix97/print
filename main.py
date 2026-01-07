import framebuf
import time
from machine import Pin

from epd2in13 import EPD

NOTES_PATH = "notes.txt"
BUTTON_PIN = 15
USB_VBUS_PIN = 24
DISPLAY_SECONDS = 15


def load_notes():
    try:
        with open(NOTES_PATH, "r") as handle:
            return [line.strip() for line in handle if line.strip()]
    except OSError:
        return []


def save_notes(notes):
    with open(NOTES_PATH, "w") as handle:
        for note in notes:
            handle.write(f"{note}\n")


def choose_note(notes):
    if not notes:
        return None, notes
    seed = int.from_bytes(bytearray(time.ticks_ms().to_bytes(4, "little")), "little")
    index = seed % len(notes)
    note = notes.pop(index)
    return note, notes


def wrap_text(text, max_chars):
    words = text.split()
    lines = []
    current = []
    for word in words:
        length = sum(len(part) for part in current) + len(current) + len(word)
        if length > max_chars and current:
            lines.append(" ".join(current))
            current = [word]
        else:
            current.append(word)
    if current:
        lines.append(" ".join(current))
    return lines


def render_note(epd, note):
    buffer = bytearray(int(epd.width * epd.height / 8))
    fb = framebuf.FrameBuffer(buffer, epd.width, epd.height, framebuf.MONO_HLSB)
    fb.fill(1)
    if note:
        max_chars = epd.width // 8
        lines = wrap_text(note, max_chars)
        max_lines = epd.height // 10
        for index, line in enumerate(lines[:max_lines]):
            fb.text(line, 0, index * 10, 0)
    else:
        fb.text("No notes left", 0, 0, 0)
    epd.display(buffer)


def main():
    button = Pin(BUTTON_PIN, Pin.IN, Pin.PULL_UP)
    usb_vbus = Pin(USB_VBUS_PIN, Pin.IN)

    epd = EPD()
    epd.init()
    epd.clear()

    while True:
        if usb_vbus.value() and button.value() == 0:
            notes = load_notes()
            note, notes = choose_note(notes)
            if note is not None:
                save_notes(notes)
            render_note(epd, note)
            time.sleep(DISPLAY_SECONDS)
            epd.clear()
            while button.value() == 0:
                time.sleep_ms(50)
        time.sleep_ms(100)


if __name__ == "__main__":
    main()
