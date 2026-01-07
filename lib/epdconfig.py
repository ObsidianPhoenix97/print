from machine import Pin, SPI
import time

RST_PIN = 12
DC_PIN = 8
CS_PIN = 9
BUSY_PIN = 13
SCK_PIN = 10
MOSI_PIN = 11
MISO_PIN = 16


class EpdConfig:
    def __init__(self):
        self.reset_pin = Pin(RST_PIN, Pin.OUT)
        self.dc_pin = Pin(DC_PIN, Pin.OUT)
        self.cs_pin = Pin(CS_PIN, Pin.OUT)
        self.busy_pin = Pin(BUSY_PIN, Pin.IN)
        self.spi = SPI(
            1,
            baudrate=2_000_000,
            polarity=0,
            phase=0,
            sck=Pin(SCK_PIN),
            mosi=Pin(MOSI_PIN),
            miso=Pin(MISO_PIN),
        )

    def digital_write(self, pin, value):
        pin.value(value)

    def digital_read(self, pin):
        return pin.value()

    def delay_ms(self, delaytime):
        time.sleep_ms(delaytime)

    def spi_writebyte(self, data):
        self.spi.write(bytearray(data))

    def module_exit(self):
        self.spi.deinit()
        self.cs_pin.init(Pin.IN)
        self.dc_pin.init(Pin.IN)
        self.reset_pin.init(Pin.IN)
