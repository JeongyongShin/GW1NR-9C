#!/usr/bin/env python
from scapy.all import *
from scapy.packet import Packet, bind_layers
from scapy.fields import ByteField, ShortField, IntField

# RoCeV2 커스텀 패킷 정의
class RoCeV2(Packet):
    name = "RoCeV2"
    fields_desc = [
        ByteField("version", 2),     # RoCeV2 버전 (일반적으로 2)
        ByteField("opcode", 0),      # RDMA 명령 종류 (예: 0x01 = RDMA Write, 0x02 = RDMA Read 등)
        ShortField("qp", 0),         # Queue Pair 번호
        IntField("psn", 0)           # Packet Sequence Number
    ]

# UDP의 dport 4791에 RoCeV2 패킷을 바인딩 (RoCeV2의 기본 포트)
bind_layers(UDP, RoCeV2, dport=4791)
bind_layers(RoCeV2, Raw)  # RoCeV2 패킷 뒤에는 Raw payload가 올 수 있음

# RoCeV2 프레임 생성 함수
def create_rocev2_packet(src_mac, dst_mac, src_ip, dst_ip, src_port, dst_port, opcode, qp, psn, payload):
    pkt = Ether(src=src_mac, dst=dst_mac) / \
          IP(src=src_ip, dst=dst_ip) / \
          UDP(sport=src_port, dport=dst_port) / \
          RoCeV2(version=2, opcode=opcode, qp=qp, psn=psn) / \
          Raw(load=payload)
    return pkt

# 생성한 RoCeV2 패킷을 전송하는 함수
def send_rocev2_packet():
    pkt = create_rocev2_packet(
        src_mac="00:11:22:33:44:55",
        dst_mac="ff:ff:ff:ff:ff:ff",
        src_ip="192.168.0.4",
        dst_ip="192.168.1.200",
        src_port=12345,
        dst_port=4791,        # RoCeV2 기본 포트
        opcode=0x01,          # 예를 들어 0x01: RDMA Write
        qp=123, 
        psn=456,
        payload="Hello RDMA!"
    )
    pkt.show()  # 생성된 패킷의 내용을 콘솔에 출력
    sendp(pkt, iface="enp5s0") # 실제 사용 중인 네트워크 인터페이스 이름으로 변경

# RoCeV2 패킷을 수신하고 분석하는 함수
def sniff_rocev2_packets():
    # UDP 포트 4791번 패킷만 필터링
    def process_packet(pkt):
        if RoCeV2 in pkt:
            print("Received RoCeV2 Packet:")
            pkt[RoCeV2].show()
    sniff(filter="udp port 4791", prn=process_packet, iface="enp5s0", count=10)

if __name__ == "__main__":
    # 테스트: 전송 또는 수신 중 하나를 실행
    send_rocev2_packet()
    # sniff_rocev2_packets()
