from epdconfig import EpdConfig


class EPD:
    width = 122
    height = 250

    def __init__(self):
        self.config = EpdConfig()
        self.reset_pin = self.config.reset_pin
        self.dc_pin = self.config.dc_pin
        self.cs_pin = self.config.cs_pin
        self.busy_pin = self.config.busy_pin
        self.spi = self.config.spi

    def _digital_write(self, pin, value):
        self.config.digital_write(pin, value)

    def _digital_read(self, pin):
        return self.config.digital_read(pin)

    def _delay_ms(self, delaytime):
        self.config.delay_ms(delaytime)

    def _spi_writebyte(self, data):
        self.config.spi_writebyte(data)

    def _reset(self):
        self._digital_write(self.reset_pin, 1)
        self._delay_ms(20)
        self._digital_write(self.reset_pin, 0)
        self._delay_ms(2)
        self._digital_write(self.reset_pin, 1)
        self._delay_ms(20)

    def _send_command(self, command):
        self._digital_write(self.dc_pin, 0)
        self._digital_write(self.cs_pin, 0)
        self._spi_writebyte([command])
        self._digital_write(self.cs_pin, 1)

    def _send_data(self, data):
        self._digital_write(self.dc_pin, 1)
        self._digital_write(self.cs_pin, 0)
        self._spi_writebyte([data])
        self._digital_write(self.cs_pin, 1)

    def _read_busy(self):
        while self._digital_read(self.busy_pin) == 1:
            self._delay_ms(10)

    def init(self):
        self._reset()
        self._send_command(0x01)
        self._send_data(0xF9)
        self._send_data(0x00)
        self._send_data(0x00)

        self._send_command(0x11)
        self._send_data(0x01)

        self._send_command(0x44)
        self._send_data(0x00)
        self._send_data(0x0F)

        self._send_command(0x45)
        self._send_data(0xF9)
        self._send_data(0x00)
        self._send_data(0x00)
        self._send_data(0x00)

        self._send_command(0x3C)
        self._send_data(0x05)

        self._send_command(0x21)
        self._send_data(0x00)
        self._send_data(0x80)

        self._send_command(0x18)
        self._send_data(0x80)

        self._send_command(0x4E)
        self._send_data(0x00)

        self._send_command(0x4F)
        self._send_data(0xF9)
        self._send_data(0x00)

        self._read_busy()

    def display(self, image):
        self._send_command(0x24)
        for byte in image:
            self._send_data(byte)
        self._turn_on_display()

    def _turn_on_display(self):
        self._send_command(0x22)
        self._send_data(0xC7)
        self._send_command(0x20)
        self._read_busy()

    def clear(self, color=0xFF):
        self._send_command(0x24)
        for _ in range(int(self.width * self.height / 8)):
            self._send_data(color)
        self._turn_on_display()

    def sleep(self):
        self._send_command(0x10)
        self._send_data(0x01)
        self._delay_ms(100)
        self.config.module_exit()
