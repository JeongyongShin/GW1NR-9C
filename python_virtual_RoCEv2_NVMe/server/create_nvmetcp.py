#!/usr/bin/env python
# -*- coding: utf-8 -*-

from scapy.all import *
from scapy.packet import Packet, bind_layers
from scapy.fields import ByteField, ShortField

# NVMe/TCP(간단히) 커스텀 패킷 정의
class NVMETCP(Packet):
    name = "NVMETCP"
    fields_desc = [
        ByteField("pdu_type", 0),  # NVMe/TCP PDU 타입(예시)
        ByteField("flags", 0),     # 플래그(예시)
        ShortField("length", 0),   # 길이 등 추가 정보(예시)
        # 실제 NVMe/TCP 헤더 구조는 훨씬 복잡합니다.
    ]

# NVMe/TCP는 일반적으로 IANA 할당 포트 4420 사용
bind_layers(TCP, NVMETCP, dport=4420)
bind_layers(NVMETCP, Raw)

def create_nvm_tcp_packet(src_mac, dst_mac, src_ip, dst_ip,
                          src_port, dst_port, pdu_type, flags, payload):
    pkt = (
        Ether(src=src_mac, dst=dst_mac) /
        IP(src=src_ip, dst=dst_ip) /
        TCP(sport=src_port, dport=dst_port) /
        NVMETCP(pdu_type=pdu_type, flags=flags, length=len(payload)) /
        Raw(load=payload)
    )
    return pkt

def send_nvm_tcp_packet():
    # 송신할 패킷 생성
    pkt = create_nvm_tcp_packet(
        src_mac="00:11:22:33:44:55",
        dst_mac="ff:ff:ff:ff:ff:ff",
        src_ip="192.168.0.10",
        dst_ip="192.168.0.20",
        src_port=50000,   # 임의의 송신 포트
        dst_port=4420,    # NVMe/TCP 기본 포트
        pdu_type=0x01,    # 예: 커맨드/데이터 구분
        flags=0x00,
        payload="Hello from NVMe/TCP!"
    )
    pkt.show()  # 패킷 구조 확인
    sendp(pkt, iface="enp5s0")  # 실제 사용 중인 인터페이스로 변경

def sniff_nvm_tcp_packets():
    # NVMe/TCP 패킷 수신 필터
    def process_packet(pkt):
        if NVMETCP in pkt:
            print("[*] Received NVMe/TCP Packet:")
            pkt[NVMETCP].show()
        else:
            print("[*] Received non-NVMe/TCP Packet:")
            pkt.show()

    sniff(filter="tcp port 4420", prn=process_packet, iface="enp5s0", count=10)

if __name__ == "__main__":
    # 테스트 시 하나만 실행
    send_nvm_tcp_packet()
    # sniff_nvm_tcp_packets()
