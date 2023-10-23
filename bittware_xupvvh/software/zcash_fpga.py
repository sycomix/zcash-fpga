

class zcash_fpga:
    import serial
    import codecs
    import struct
    import struct

    def byt_to_ver(self):
        return f'v{self[2]}.{self[1]}.{self[0]}'

    def byt_to_str(self):
        return self[::-1].decode("utf-8")

    def byt_to_hex(self):
        return f'0x{self.hex()}'

    def byt_to_int(self):
        return int.from_bytes(self, byteorder='little')

    fpga_msg_type_dict = {'FPGA_IGNORE_RPL':int('80000002', 16),
                          'FPGA_STATUS_RPL':int('80000001', 16),
                          'RESET_FPGA_RPL':int('80000000', 16),
                          'VERIFY_SECP256K1_SIG_RPL':int('80000101', 16),
                          'VERIFY_EQUIHASH_RPL':int('80000100', 16)}

    fpga_msg_dict = {fpga_msg_type_dict['VERIFY_SECP256K1_SIG_RPL']:{'name':'VERIFY_SECP256K1_SIG_RPL', 'feilds':[(8, 'index', byt_to_int), (1, 'bm', byt_to_hex), (2, 'cycle_cnt', byt_to_int)]},
                     fpga_msg_type_dict['FPGA_IGNORE_RPL']:{'name':'FPGA_IGNORE_RPL', 'feilds':[(8, 'ignored_header', byt_to_hex)]},
                     fpga_msg_type_dict['FPGA_STATUS_RPL']:{'name':'FPGA_STATUS_RPL', 'feilds':[(4, 'version', byt_to_ver), (8, 'build_date', byt_to_str), (8, 'buid_host', byt_to_str), (8, 'cmd_cap', byt_to_hex)]},
                     fpga_msg_type_dict['RESET_FPGA_RPL']:{'name':'RESET_FPGA_RPL', 'feilds':[]},
                     fpga_msg_type_dict['VERIFY_EQUIHASH_RPL']:{'name':'VERIFY_EQUIHASH_RPL', 'feilds':[(8, 'index', byt_to_int), (1, 'bm', byt_to_hex)]}}


    def __init__(self, COM='COM4', get_status=True):
        self.s = self.serial.Serial(COM, 921600, timeout=1)
        #Test getting FPGA status
        if get_status:
            self.get_status()
        print("Connected...")

    # FPGA status
    def get_status(self):
        self.s.write(self.codecs.decode('0800000001000000', 'hex'))
        # Parse reply
        self.get_reply()

    def reset_fpga(self):
        self.s.write(self.codecs.decode('0800000000000000', 'hex'))
        # Parse reply - should be reset
        res = self.get_reply()[0]
        if (self.struct.unpack('<I', res[4:8])[0] != self.fpga_msg_type_dict['RESET_FPGA_RPL']):
            print("ERROR: Reply type was not RESET_FPGA_RPL")

    def get_reply(self):
        res = self.s.read(1024)
        print(res)
        msg_list = self.parse_reply(res)
        if msg_list and len(msg_list) > 0:
            for msg in msg_list:
                self.print_reply(msg)
            return msg_list
        else:
            print ("INFO: No reply received")
            return None

    def secp256k1_verify_sig(self, index, hsh, r, s, Qx, Qy):
        cmd = '00000101000000B0'
        cmd = format(index, 'x').rjust(16, '0') + cmd
        cmd = format(s, 'x').rjust(64, '0') + cmd
        cmd = format(r, 'x').rjust(64, '0') + cmd
        cmd = format(hsh, 'x').rjust(64, '0') + cmd
        cmd = format(Qx, 'x').rjust(64, '0') + cmd
        cmd = format(Qy, 'x').rjust(64, '0') + cmd
        #Need to swap cmd byte order
        cmd = "".join(reversed([cmd[i:i+2] for i in range(0, len(cmd), 2)]))
        self.s.write(self.codecs.decode(cmd, 'hex'))
        res = self.get_reply()[0] # Just look at the first reply
        if res is not None and (self.struct.unpack('<I', res[4:8])[0] != self.fpga_msg_type_dict['VERIFY_SECP256K1_SIG_RPL']):
            print("ERROR: Reply type was not VERIFY_SECP256K1_SIG_RPL")
            return False
        if (self.struct.unpack('<Q', res[8:16])[0] != index):
            print("ERROR: Index did not match")
            return False
        if (self.struct.unpack('<B', res[16:17])[0] != 0):
            print("ERROR: Result bitmask was non-zero")
            return False
        print("INFO: Secp256k1 signature verified correctly")
        return True

    def equihash_verify(self, index, hdr):
        cmd = '00000100000005df'
        cmd = format(index, 'x').rjust(16, '0') + cmd

        #Need to swap cmd byte order
        cmd = "".join(reversed([cmd[i:i+2] for i in range(0, len(cmd), 2)]))

        #Add on binary data for header since it is already in correct format

        cmd += hdr.rjust(1487, '0')
        self.s.write(self.codecs.decode(cmd, 'hex'))
        res = self.get_reply()[0] # Just look at the first reply
        if res is not None and (self.struct.unpack('<I', res[4:8])[0] != self.fpga_msg_type_dict['VERIFY_EQUIHASH_RPL']):
            print("ERROR: Reply type was not VERIFY_EQUIHASH_RPL")
            return False
        if (self.struct.unpack('<Q', res[8:16])[0] != index):
            print("ERROR: Index did not match")
            return False
        if (self.struct.unpack('<B', res[16:17])[0] != 0):
            print("ERROR: Result bitmask was non-zero")
            return False
        print("INFO: Equihash solution verified correctly")
        return True

    def close(self):
        self.s.close()
        print("Closed...")

    def parse_reply(self, msg, msg_list = None):
        if msg_list is None:
            msg_list = []
        if (len(msg) >= 8):
            length = self.struct.unpack('<I', msg[:4])[0]
            if length == 0:
                return msg_list
            msg_list.append(msg[:length])
            if (len(msg) > length):
                self.parse_reply(msg[length:], msg_list)
        return msg_list

    def print_reply(self, msg):
        cmd = (self.struct.unpack('<I', msg[4:8])[0])
        if (cmd not in self.fpga_msg_dict):
            print("ERROR: Unknown message type:", cmd)

        print ("INFO: Received ", self.fpga_msg_dict[cmd]['name'])
        offset = 8
        for i in range(len(self.fpga_msg_dict[cmd]['feilds'])):
            length = self.fpga_msg_dict[cmd]['feilds'][i][0]
            print(self.fpga_msg_dict[cmd]['feilds'][i][1], ":", self.fpga_msg_dict[cmd]['feilds'][i][2](bytes(msg[offset:offset+length])))
            offset += length   

#Example usages:
def example_secp256k1_sig():
    zf = zcash_fpga()
    index = 1
    hsh = 34597931798561447004034205848155169322219865803759328163562698792725658370004
    r = 550117237093786687120086685263208063857013211911888854762107796665370524299
    s = 100440748044460701692736849796872767381221821858945401325418288486792652245963
    Qx = 58140175961173984744358741087164846868370435294166601807987768465943227655092
    Qy = 108022006572115270940875378266056879700669412417454111206384551596343133676105
    zf.secp256k1_verify_sig(index, hsh, r, s, Qx, Qy)
    zf.close()

def example_equihash_verif():
    zf = zcash_fpga('COM4', False)
    index = 1
    with open("../../zcash_fpga/src/data/block_346.bin", "rb") as header_file:
        data = header_file.read()
        zf.equihash_verify(index, data.hex())
    zf.close()   

#example_secp256k1_sig()
example_equihash_verif()
