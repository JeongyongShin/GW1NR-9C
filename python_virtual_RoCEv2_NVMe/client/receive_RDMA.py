from scapy.all import sniff, UDP, Raw, Packet, bind_layers, ByteField, ShortField, IntField

# RoCeV2 커스텀 패킷 계층 정의
class RoCeV2(Packet):
    name = "RoCeV2"
    fields_desc = [
        ByteField("version", 2),  # RoCeV2 버전 (보통 2)
        ByteField("opcode", 0),   # RDMA 명령 종류 (예: 0x01 = RDMA Write 등)
        ShortField("qp", 0),      # Queue Pair 번호
        IntField("psn", 0)        # Packet Sequence Number
    ]

# UDP의 목적지 포트가 4791일 때 RoCeV2 계층으로 인식하도록 바인딩
bind_layers(UDP, RoCeV2, dport=4791)
bind_layers(RoCeV2, Raw)  # RoCeV2 계층 뒤에는 Raw payload가 올 수 있음

def process_packet(pkt):
    if RoCeV2 in pkt:
        print("Received RoCeV2 Packet:")
        pkt[RoCeV2].show()
    else:
        print("Received packet without RoCeV2 layer:")
        pkt.show()

# 실제 사용 중인 네트워크 인터페이스 이름으로 변경 (예: "Wi-Fi")
sniff(filter="udp port 4791", prn=process_packet, iface="Wi-Fi")
