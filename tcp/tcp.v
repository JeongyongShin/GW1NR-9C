// ======================================================================
// NVMe/TCP Emulator for Tang Nano 9K Board with NVMe/TCP Packet Write to Memory
// - btn1: falling edge 시 NVMe/TCP 패킷을 생성하여 메모리(mem[])에 write
//         (패킷 구성: version, opcode, flags, cmd id, NSID, payload "Hello NVMe/TCP!")
// - btn1 완료 후 "W OK"가 UART TX를 통해 전송됨
// - btn2: 기존 read 동작 ("R OK" 전송)
// ======================================================================
module tcp_offload (
    input  wire       clk,
    input  wire       uart_rx,  // 미사용 (제약 파일 포함)
    input  wire       btn1,     // Write 동작: active low (Pin3)
    input  wire       btn2,     // Read 동작: active low (Pin4, JTAG_SEL)
    output wire       uart_tx,
    output wire [5:0] led       // LED[0] ~ LED[5]
);

    parameter BAUD_DIV = 234;  // Tang Nano 9K 보드 클럭에 맞게 조정

    // FSM 상태 정의
    localparam STATE_IDLE       = 0;
    // "R OK" 전송 상태
    localparam STATE_SEND_R0    = 7;  // 'R'
    localparam STATE_SEND_R1    = 8;  // ' ' (공백)
    localparam STATE_SEND_R2    = 9;  // 'O'
    localparam STATE_SEND_R3    = 10; // 'K'
    // "W OK" 전송 상태 (패킷 write 완료 후 확인 메시지)
    localparam STATE_SEND_W0    = 11; // 'W'
    localparam STATE_SEND_W1    = 12; // ' ' (공백)
    localparam STATE_SEND_W2    = 13; // 'O'
    localparam STATE_SEND_W3    = 14; // 'K'
    // NVMe/TCP 패킷을 메모리에 write하는 상태
    localparam STATE_NVME_WRITE = 15;

    reg [3:0] state;
    // UART TX 관련 신호
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;

    // 내부 메모리 (256 Byte)
    reg [7:0] mem [0:255];

    // 버튼 Edge Detection 용: 이전 상태 저장 (active low)
    reg btn1_prev, btn2_prev;

    // NVMe/TCP 패킷 write 관련
    reg [4:0] pkt_idx;         // 패킷 길이 23바이트 -> 인덱스 0~22
    localparam PACKET_LENGTH = 23;

    // NVMe/TCP 패킷 생성 함수 
    // (패킷 구성: version, opcode, flags, cmd id, NSID, payload "Hello NVMe/TCP!")
    function [7:0] packet_data;
        input [4:0] index;
        begin
            case(index)
                // NVMe/TCP 헤더 (8바이트)
                0:  packet_data = 8'h01; // version = 1
                1:  packet_data = 8'h00; // opcode  = 0x00 (NVMe Write)
                2:  packet_data = 8'h00; // flags (예시)
                3:  packet_data = 8'h01; // command identifier = 1
                4:  packet_data = 8'h00; // NSID byte [31:24]
                5:  packet_data = 8'h00; // NSID byte [23:16]
                6:  packet_data = 8'h00; // NSID byte [15:8]
                7:  packet_data = 8'h01; // NSID byte [7:0]  (예: 1)
                // Payload: "Hello NVMe/TCP!" (15바이트)
                8:  packet_data = "H";
                9:  packet_data = "e";
                10: packet_data = "l";
                11: packet_data = "l";
                12: packet_data = "o";
                13: packet_data = " ";
                14: packet_data = "N";
                15: packet_data = "V";
                16: packet_data = "M";
                17: packet_data = "e";
                18: packet_data = "/";
                19: packet_data = "T";
                20: packet_data = "C";
                21: packet_data = "P";
                22: packet_data = "!";
                default: packet_data = 8'h00;
            endcase
        end
    endfunction

    // UART Transmitter 모듈 인스턴스
    uart_tx #(.BAUD_DIV(BAUD_DIV)) uart_tx_inst (
        .clk(clk),
        .tx_start(tx_start),
        .data(tx_data),
        .tx(uart_tx),
        .busy(tx_busy)
    );

    // 초기화
    initial begin
        state     = STATE_IDLE;
        tx_start  = 0;
        btn1_prev = 1;
        btn2_prev = 1;
        pkt_idx   = 0;
    end

    // 메인 FSM: 버튼 Edge Detection 및 각 상태별 동작
    always @(posedge clk) begin
        // UART TX 전송 요청 신호는 한 사이클만 유지
        if (tx_start && !tx_busy)
            tx_start <= 0;

        // STATE_IDLE 상태에서 버튼 falling edge 검출
        if (state == STATE_IDLE) begin
            if ((btn1_prev == 1) && (btn1 == 0)) begin
                pkt_idx <= 0;              // 패킷 인덱스 초기화
                state   <= STATE_NVME_WRITE; // NVMe/TCP 패킷 write 시작
            end else if ((btn2_prev == 1) && (btn2 == 0)) begin
                state   <= STATE_SEND_R0;    // btn2: 기존 read ("R OK") 처리
            end
        end

        // FSM 상태에 따른 동작 처리
        case (state)
            // NVMe/TCP 패킷을 메모리에 write하는 상태
            STATE_NVME_WRITE: begin
                // 매 clk마다 하나의 패킷 바이트를 메모리의 해당 주소에 기록
                mem[pkt_idx] <= packet_data(pkt_idx);
                if (pkt_idx == PACKET_LENGTH - 1) begin
                    pkt_idx <= 0;
                    state   <= STATE_SEND_W0; // 패킷 write 완료 후 "W OK" 전송
                end else begin
                    pkt_idx <= pkt_idx + 1;
                end
            end

            // "R OK" 전송 (btn2 read 명령)
            STATE_SEND_R0: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= "R";
                    tx_start <= 1;
                    state   <= STATE_SEND_R1;
                end
            end
            STATE_SEND_R1: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= " ";
                    tx_start <= 1;
                    state   <= STATE_SEND_R2;
                end
            end
            STATE_SEND_R2: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= "O";
                    tx_start <= 1;
                    state   <= STATE_SEND_R3;
                end
            end
            STATE_SEND_R3: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= "K";
                    tx_start <= 1;
                    state   <= STATE_IDLE;
                end
            end

            // "W OK" 전송 (btn1 write 후 확인 메시지)
            STATE_SEND_W0: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= "W";
                    tx_start <= 1;
                    state   <= STATE_SEND_W1;
                end
            end
            STATE_SEND_W1: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= " ";
                    tx_start <= 1;
                    state   <= STATE_SEND_W2;
                end
            end
            STATE_SEND_W2: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= "O";
                    tx_start <= 1;
                    state   <= STATE_SEND_W3;
                end
            end
            STATE_SEND_W3: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= "K";
                    tx_start <= 1;
                    state   <= STATE_IDLE;
                end
            end

            default: ; // 그 외 상태는 별도 처리 없음
        endcase

        // 버튼의 이전 상태 업데이트 (edge detection)
        btn1_prev <= btn1;
        btn2_prev <= btn2;
    end

    // LED 제어: 버튼이 눌리면 LED[0] = 0, 그렇지 않으면 1
    assign led[0] = ((btn1 == 0) || (btn2 == 0)) ? 1'b0 : 1'b1;
    assign led[1] = 1'b1;
    assign led[2] = 1'b1;
    assign led[3] = 1'b1;
    assign led[4] = 1'b1;
    assign led[5] = 1'b1;

endmodule

// ======================================================================
// 간단한 UART Transmitter 모듈 구현
// ======================================================================
module uart_tx #(parameter BAUD_DIV = 234)(
    input  wire clk,
    input  wire tx_start,
    input  wire [7:0] data,
    output reg tx,
    output reg busy
);
    localparam TX_IDLE  = 0;
    localparam TX_START = 1;
    localparam TX_DATA  = 2;
    localparam TX_STOP  = 3;

    reg [1:0] state;
    reg [15:0] counter;
    reg [2:0] bit_index;
    reg [7:0] tx_shift;

    initial begin
        state     = TX_IDLE;
        counter   = 0;
        bit_index = 0;
        busy      = 0;
        tx        = 1;
    end

    always @(posedge clk) begin
        case (state)
            TX_IDLE: begin
                tx <= 1;
                busy <= 0;
                counter <= 0;
                bit_index <= 0;
                if (tx_start) begin
                    busy <= 1;
                    tx_shift <= data;
                    state <= TX_START;
                end
            end
            TX_START: begin
                tx <= 0;  // 시작 비트
                if (counter < BAUD_DIV - 1)
                    counter <= counter + 1;
                else begin
                    counter <= 0;
                    state <= TX_DATA;
                end
            end
            TX_DATA: begin
                tx <= tx_shift[0];
                if (counter < BAUD_DIV - 1)
                    counter <= counter + 1;
                else begin
                    counter <= 0;
                    tx_shift <= tx_shift >> 1;
                    if (bit_index < 7)
                        bit_index <= bit_index + 1;
                    else begin
                        bit_index <= 0;
                        state <= TX_STOP;
                    end
                end
            end
            TX_STOP: begin
                tx <= 1;  // 정지 비트
                if (counter < BAUD_DIV - 1)
                    counter <= counter + 1;
                else begin
                    counter <= 0;
                    state <= TX_IDLE;
                end
            end
            default: state <= TX_IDLE;
        endcase
    end
endmodule
