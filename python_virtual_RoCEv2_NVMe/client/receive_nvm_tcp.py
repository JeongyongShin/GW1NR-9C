# -*- coding: utf-8 -*-

from scapy.all import sniff, TCP, Raw
from scapy.packet import Packet, bind_layers
from scapy.fields import ByteField, ShortField

# NVMe/TCP(간단히) 커스텀 패킷 정의 (Windows 쪽도 동일하게 정의)
class NVMETCP(Packet):
    name = "NVMETCP"
    fields_desc = [
        ByteField("pdu_type", 0),
        ByteField("flags", 0),
        ShortField("length", 0),
    ]

bind_layers(TCP, NVMETCP, dport=4420)
bind_layers(NVMETCP, Raw)

def process_packet(pkt):
    if NVMETCP in pkt:
        print("[*] Received NVMe/TCP Packet:")
        pkt[NVMETCP].show()
    else:
        print("[*] Received packet without NVMe/TCP layer:")
        pkt.show()

if __name__ == "__main__":
    # Windows에서 사용 중인 실제 인터페이스 이름으로 교체 (예: "Ethernet", "Wi-Fi")
    sniff(filter="tcp port 4420", prn=process_packet, iface="Wi-Fi")
