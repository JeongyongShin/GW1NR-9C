`default_nettype none

module uart
#(
    parameter DELAY_FRAMES = 234  // 27MHz / 115200 Baud
)
(
    input  wire       clk,
    input  wire       uart_rx,
    output wire       uart_tx,
    output reg  [5:0] led,
    // 두 개의 버튼 입력 (active low)
    input  wire       btn1,   // 기존 버튼 (Pin3)
    input  wire       btn2    // 두 번째 버튼 (Pin4, JTAG_SEL)
);

// --------------------------------------------------
// 1) UART RX (수신부) -- 기존 코드 그대로 사용
// --------------------------------------------------
localparam HALF_DELAY_WAIT = (DELAY_FRAMES / 2);

reg [3:0]  rxState    = 0;
reg [12:0] rxCounter  = 0;
reg [7:0]  dataIn     = 0;
reg [2:0]  rxBitNumber= 0;
reg        byteReady  = 0;

localparam RX_STATE_IDLE      = 0;
localparam RX_STATE_START_BIT = 1;
localparam RX_STATE_READ_WAIT = 2;
localparam RX_STATE_READ      = 3;
localparam RX_STATE_STOP_BIT  = 5;

always @(posedge clk) begin
    case (rxState)
        RX_STATE_IDLE: begin
            if (uart_rx == 0) begin
                rxState    <= RX_STATE_START_BIT;
                rxCounter  <= 1;
                rxBitNumber<= 0;
                byteReady  <= 0;
            end
        end 

        RX_STATE_START_BIT: begin
            if (rxCounter == HALF_DELAY_WAIT) begin
                rxState   <= RX_STATE_READ_WAIT;
                rxCounter <= 1;
            end else 
                rxCounter <= rxCounter + 1;
        end

        RX_STATE_READ_WAIT: begin
            rxCounter <= rxCounter + 1;
            if ((rxCounter + 1) == DELAY_FRAMES) begin
                rxState <= RX_STATE_READ;
            end
        end

        RX_STATE_READ: begin
            rxCounter <= 1;
            // 새 비트를 MSB로 받아서 dataIn을 오른쪽으로 shift
            dataIn    <= {uart_rx, dataIn[7:1]};
            rxBitNumber <= rxBitNumber + 1;
            if (rxBitNumber == 3'b111)
                rxState <= RX_STATE_STOP_BIT;
            else
                rxState <= RX_STATE_READ_WAIT;
        end

        RX_STATE_STOP_BIT: begin
            rxCounter <= rxCounter + 1;
            if ((rxCounter + 1) == DELAY_FRAMES) begin
                rxState   <= RX_STATE_IDLE;
                rxCounter <= 0;
                byteReady <= 1;  // 한 바이트 수신 완료
            end
        end
    endcase
end

// --------------------------------------------------
// (추가) 메시지 수신 시 LED[3] 토글을 위한 로직
// byteReady의 상승 에지를 검출하여 led3_state를 반전시킴
// --------------------------------------------------
reg led3_state = 1;      // 초기값: off (active low: 1 = off, 0 = on)
reg byteReady_prev = 0;

always @(posedge clk) begin
    byteReady_prev <= byteReady;       // 이전 byteReady 값을 저장
    // byteReady가 0에서 1로 상승할 때 LED[3] 상태 토글
    if (byteReady && !byteReady_prev) begin
        led3_state <= ~led3_state;
    end
end

// --------------------------------------------------
// 1. 주요 수정 부분: LED 업데이트 로직 수정
// 버튼 입력에 따른 LED 제어 대신, 
// LED[3]는 메시지 수신에 따라 토글되고, 나머지 LED는 항상 off(1)로 유지
// --------------------------------------------------
always @(posedge clk) begin
    led[0] <= 1;         // off
    led[1] <= 1;         // off
    led[2] <= 1;         // off
    led[3] <= led3_state; // 토글 상태 반영
    led[4] <= 1;         // off
    led[5] <= 1;         // off

    if ((btn1 == 0) || (btn2 == 0))
        led[0] <= 0;  // 버튼 눌림 -> LED[0] 켜짐 (0)
    else
        led[0] <= 1;  // 버튼 안 눌림 -> LED[0] 꺼짐 (1)

end




// --------------------------------------------------
// 2) UART TX (송신부) -- 버튼에 따라 다른 문자열 전송
// --------------------------------------------------
reg [3:0]  txState       = 0;
reg [24:0] txCounter     = 0;
reg [7:0]  dataOut       = 0;
reg        txPinRegister = 1;
reg [2:0]  txBitNumber   = 0;

// 어떤 메시지를 전송할지 선택 (0: "Lushay Labs ", 1: "hello ")
reg        messageSelect = 0;

assign uart_tx = txPinRegister;

// --------- 첫 번째 메시지 ("Lushay Labs ") ---------
localparam MEMORY_LENGTH1 = 12;
reg [7:0] testMemory1 [MEMORY_LENGTH1-1:0];

initial begin
    testMemory1[0]  = "L";
    testMemory1[1]  = "u";
    testMemory1[2]  = "s";
    testMemory1[3]  = "h";
    testMemory1[4]  = "a";
    testMemory1[5]  = "y";
    testMemory1[6]  = " ";
    testMemory1[7]  = "L";
    testMemory1[8]  = "a";
    testMemory1[9]  = "b";
    testMemory1[10] = "s";
    testMemory1[11] = " ";
end

// --------- 두 번째 메시지 ("hello ") ---------
localparam MEMORY_LENGTH2 = 6;
reg [7:0] testMemory2 [MEMORY_LENGTH2-1:0];

initial begin
    testMemory2[0] = "h";
    testMemory2[1] = "e";
    testMemory2[2] = "l";
    testMemory2[3] = "l";
    testMemory2[4] = "o";
    testMemory2[5] = " ";  // 뒤에 공백 추가
end

reg [3:0] txByteCounter = 0;

// TX 상태 정의
localparam TX_STATE_IDLE      = 0;
localparam TX_STATE_START_BIT = 1;
localparam TX_STATE_WRITE     = 2;
localparam TX_STATE_STOP_BIT  = 3;
localparam TX_STATE_DEBOUNCE  = 4;

always @(posedge clk) begin
    case (txState)
        // 대기 상태: btn1(핀3) 또는 btn2(핀4)가 눌리면 메시지 전송 시작
        TX_STATE_IDLE: begin
            txPinRegister <= 1;  // 유휴 시 TX는 HIGH
            if (btn1 == 0) begin
                messageSelect <= 0;           // "Lushay Labs "
                txState       <= TX_STATE_START_BIT;
                txCounter     <= 0;
                txByteCounter <= 0;
            end
            else if (btn2 == 0) begin
                messageSelect <= 1;           // "hello "
                txState       <= TX_STATE_START_BIT;
                txCounter     <= 0;
                txByteCounter <= 0;
            end
        end

        // 시작 비트 전송 (LOW)
        TX_STATE_START_BIT: begin
            txPinRegister <= 0;
            if ((txCounter + 1) == DELAY_FRAMES) begin
                txState    <= TX_STATE_WRITE;
                txBitNumber<= 0;
                txCounter  <= 0;
                // 전송할 문자 선택
                if (messageSelect == 0)
                    dataOut <= testMemory1[txByteCounter];
                else
                    dataOut <= testMemory2[txByteCounter];
            end else 
                txCounter <= txCounter + 1;
        end

        // 데이터 비트 전송 (LSB부터)
        TX_STATE_WRITE: begin
            txPinRegister <= dataOut[txBitNumber];
            if ((txCounter + 1) == DELAY_FRAMES) begin
                txCounter <= 0;
                if (txBitNumber == 3'b111) begin
                    txState <= TX_STATE_STOP_BIT;
                end else begin
                    txBitNumber <= txBitNumber + 1;
                end
            end else 
                txCounter <= txCounter + 1;
        end

        // 정지 비트 전송 (HIGH)
        TX_STATE_STOP_BIT: begin
            txPinRegister <= 1;
            if ((txCounter + 1) == DELAY_FRAMES) begin
                txCounter <= 0;
                // 다음 바이트로 넘어갈지, 모든 바이트 전송 끝났는지 확인
                if (messageSelect == 0) begin
                    // "Lushay Labs "
                    if (txByteCounter == MEMORY_LENGTH1 - 1) begin
                        txState <= TX_STATE_DEBOUNCE;
                    end else begin
                        txByteCounter <= txByteCounter + 1;
                        txState <= TX_STATE_START_BIT;
                    end
                end else begin
                    // "hello "
                    if (txByteCounter == MEMORY_LENGTH2 - 1) begin
                        txState <= TX_STATE_DEBOUNCE;
                    end else begin
                        txByteCounter <= txByteCounter + 1;
                        txState <= TX_STATE_START_BIT;
                    end
                end
            end else 
                txCounter <= txCounter + 1;
        end

        // 디바운스: 버튼이 떼어질 때까지 대기
        TX_STATE_DEBOUNCE: begin
            if (txCounter == 23'b11111111111111111111111) begin
                // 두 버튼 모두 떼어졌으면 IDLE 복귀
                if (btn1 == 1 && btn2 == 1) 
                    txState <= TX_STATE_IDLE;
            end else
                txCounter <= txCounter + 1;
        end
    endcase      
end

endmodule
