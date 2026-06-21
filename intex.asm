
; sdas8051  -o ./intex.asm
; sdld -i ./intex.rel
; packihx ./intex.ihx > intex.hex
; ./sn8flash --port /dev/ttyUSB0 --reset-less write --file ./intex.hex

;------------------------------------------------------------------------------------

.module intex

; MCU Options
; Program Memory Security 0x01 = Disable, 0x00 = Enable
SECURITY_SET    .equ     0x01

; CPU Clock Source 0x07 = IHRC 32 MHz
CLOCKSRC_SET    .equ     0x07

; External Reset / GPIO Shared Pin 0x00 = Reset with De-bounce 0x02 = Reset without De-bounce 0x03 = GPIO
RESETPIN_SET    .equ     0x03

; Watchdog Reset 0x00 = Always, 0x05 = Enable, 0x0A = Disable
WATCHDOG_SET    .equ     0x0a

; Watchdog Overflow Period 0x00 = 64ms, 0x01 = 128ms, 0x02 = 256ms, 0x03 = 512ms
WATCHCLK_SET    .equ     0x03

.area CSEG (ABS, CODE)
.org 0x0ff6
.db      0xff
.db      0xff
.db      0xff
.db      0xff
.db      0xff
.db      0xff
.db      WATCHCLK_SET << 6 | RESETPIN_SET << 4 | 0x06
.db      0x5a
.db      0xa5
.db      WATCHDOG_SET << 4 | CLOCKSRC_SET << 1 | SECURITY_SET

;----------------------------------------------------------

; Define SFR
P0M .equ 0xf9
P1M .equ 0xfa
P2M .equ 0xfb
PECMD .equ 0x94 ; ISP command
PEROML .equ 0x95 ; flash address low byte
PEROMH .equ 0x96 ; flash address high byte
PERAM .equ 0x97 ; RAM mapping/data register

;----- variables -----

COUNTER           .equ 0x30
BUT1_MODE         .equ 0x31
BUT1_CNT          .equ 0x32
BUT2_MODE         .equ 0x33
BUT2_CNT          .equ 0x34
LED_MODE          .equ 0x35
LAMP_MODE         .equ 0x36
LAMP_CYCLING_MODE .equ 0x37
LAMP_CYCLING_CNT  .equ 0x38
RED_PWM_H         .equ 0x39
RED_PWM_L         .equ 0x3a
GREEN_PWM_H       .equ 0x3b
GREEN_PWM_L       .equ 0x3c
BLUE_PWM_H        .equ 0x3d
BLUE_PWM_L        .equ 0x3e
PREV_LIGHT        .equ 0x3f
ISP_BUFFER        .equ 0x40 ; 32 bytes

;----- aliases -----

P_RGB_PWR  .equ P1.4
P_RED      .equ P0.0
P_GREEN    .equ P0.6
P_BLUE     .equ P1.2

P_BUT1     .equ P1.3
P_BUT2     .equ P0.7

P_LAMP_PWR .equ P0.1
P_LIGHT    .equ P2.0

store_addr .equ 0xfc0

;----- code -----

.area INTV (ABS)

.org 0x0000
_int_reset:
    ljmp main

.org 0x000b
_int_timer0:
    ljmp timer0

.area CSEG (ABS, CODE)

.org 0x0090

;------------------------------------
; ~128 Hz interrupt

timer0:

    push ACC
    push PSW

    mov TH0, #0xae ; Reload timer
    mov TL0, #0x9f

    inc COUNTER

    mov a, BUT1_MODE
    cjne a, #0x00, but1_1
    jb P_BUT1, but2_0

    inc LED_MODE
    mov a, LED_MODE
    cjne a, #0x07, but1_0
    mov LED_MODE, #0x00

but1_0:

    acall store_modes
    mov a, r0
    mov r0, SP
    dec r0
    dec r0
    mov @r0, #>led_mode_init
    dec r0
    mov @r0, #<led_mode_init
    mov r0, a

    mov BUT1_CNT, #0x14
    mov BUT1_MODE, #0x01
    sjmp but2_0

but1_1:

    cjne a, #0x01, but1_2
    djnz BUT1_CNT, but2_0
    mov BUT1_MODE, #0x02
    sjmp but2_0

but1_2:

    cjne a, #0x02, but1_3
    jnb P_BUT1, but2_0
    mov BUT1_CNT, #0x14
    mov BUT1_MODE, #0x03
    sjmp but2_0

but1_3:

    cjne a, #0x03, but2_0
    djnz BUT1_CNT, but2_0
    mov BUT1_MODE, #0x00

but2_0:

    mov a, BUT2_MODE
    cjne a, #0x00, but2_4
    jb P_BUT2, but2_7

    inc LAMP_MODE
    mov a, LAMP_MODE
    cjne a, #0x02, but2_1
    mov LAMP_MODE, #0x00

but2_1:

    acall store_modes
    ; set lamp power
    mov a, LAMP_MODE
    cjne a, #0x01, but2_2
    setb P_LAMP_PWR
    sjmp but2_3

but2_2:

    clr P_LAMP_PWR

but2_3:

    mov BUT2_CNT, #0x14
    mov BUT2_MODE, #0x01
    sjmp but2_7

but2_4:

    cjne a, #0x01, but2_5
    djnz BUT2_CNT, but2_7
    mov BUT2_MODE, #0x02
    sjmp but2_7

but2_5:

    cjne a, #0x02, but2_6
    jnb P_BUT2, but2_7
    mov BUT2_CNT, #0x14
    mov BUT2_MODE, #0x03
    sjmp but2_7

but2_6:

    cjne a, #0x03, but2_7
    djnz BUT2_CNT, but2_7
    mov BUT2_MODE, #0x00

but2_7:

    mov a, LAMP_CYCLING_MODE
    cjne a, #0x01, c0
    djnz LAMP_CYCLING_CNT, c1
    clr P_LAMP_PWR
    mov LAMP_CYCLING_MODE, #0x02
    mov LAMP_CYCLING_CNT, #0x0a
    sjmp c1

c0:

    cjne a, #0x02, c1
    djnz LAMP_CYCLING_CNT, c1
    setb P_LAMP_PWR
    mov LAMP_CYCLING_MODE, #0x00 ;done

c1:

    jnb P_LIGHT, l0 ; jump if light is on
    mov a, PREV_LIGHT
    jnz l1
    ; led and lamp was off, now turn on
    mov PREV_LIGHT, #0x01
    setb P_RGB_PWR ; enable RGB LEDs power
    mov a, LAMP_MODE
    cjne a, #0x01, l1
    setb P_LAMP_PWR ; turn on lamp power
    mov LAMP_CYCLING_MODE, #0x01 ; will cycle lamp power
    mov LAMP_CYCLING_CNT, #0x0a
    sjmp l1

l0:

    mov a, PREV_LIGHT
    jz l1
    clr P_RGB_PWR ;turn off leds
    clr P_LAMP_PWR ;turn off lamp
    mov LAMP_CYCLING_MODE, #0x00
    mov PREV_LIGHT, #0x00

l1:

    pop PSW
    pop ACC
    reti

;----- init variables, timer0 interrupt, pins -----

main:

    mov COUNTER, #0x00

    mov BUT1_MODE, #0x00
    mov BUT1_CNT, #0x00

    mov BUT2_MODE, #0x00
    mov BUT2_CNT, #0x00

    mov LED_MODE, #0x00
    mov LAMP_MODE, #0x00

    acall load_modes ; try to load LED and LAMP modes from the flash

    ; set lamp power
    mov a, LAMP_MODE
    cjne a, #0x01, main0
    jnb P_LIGHT, main0; light is on, don't turn on lamp
    setb P_LAMP_PWR
    mov LAMP_CYCLING_MODE, #0x01 ; will cycle lamp power
    mov LAMP_CYCLING_CNT, #0x0a
    sjmp main1

main0:

    clr P_LAMP_PWR
    mov LAMP_CYCLING_MODE, #0x00

main1:

    mov TH0, #0xae ; Reload for ~128 Hz
    mov TL0, #0x9f
    mov TMOD, #0x01 ; Set Timer0 to 16 bit counter mode
    setb ET0 ; Enable Timer0 interrupt
    setb EA  ; Global interrupt enable
    setb TR0 ; Start Timer0

    mov P0M, #0x43  ; Sets P0.0, P0.1, P0.6 to push-pull output mode
    mov P1M, #0x14  ; Sets P1.2, P1.4 to push-pull output mode

    clr P_RED
    clr P_GREEN
    clr P_BLUE

    jnb P_LIGHT, main2 ; light is on, don't turn on leds
    setb P_RGB_PWR ; enable RGB LEDs power
    mov PREV_LIGHT, #0x01
    sjmp main3

main2:

    clr P_RGB_PWR ; disable RGB LEDs power
    mov PREV_LIGHT, #0x00

main3:

;------- entry at reset and LED mode switch

led_mode_init:

    mov a, LED_MODE
    cjne a, #0x00, m0

    ; mode 0, off

    clr P_RED
    clr P_GREEN
    clr P_BLUE

m0:

    cjne a, #0x01, m1
    ; mode 1, RGB
    setb P_RED
    setb P_GREEN
    setb P_BLUE

m1:

    cjne a, #0x02, m2
    ; mode 2, G
    clr P_RED
    setb P_GREEN
    clr P_BLUE

m2:

    cjne a, #0x03, m3
    ; mode 3, GB
    clr P_RED
    setb P_GREEN
    setb P_BLUE

m3:

    cjne a, #0x04, m4
    ; mode 4, B
    clr P_RED
    clr P_GREEN
    setb P_BLUE

m4:

    cjne a, #0x05, m5
    ; mode 5, BR
    setb P_RED
    clr P_GREEN
    setb P_BLUE

m5:

    cjne a, #0x06, m5 ; loop there if incorrect led mode

    clr P_RED
    clr P_GREEN
    clr P_BLUE

flash_mode:

    ; GREEN DOWN, BLUE UP

    mov dptr, #led_gamma_table_end
    mov r1, dpl
    mov r2, dph

    mov dptr, #led_gamma_table
    mov r3, dpl
    mov r4, dph

    mov r6, #0x04
    mov r7, #0xe8
    mov r5, COUNTER

gdbu_0:

    inc r5
    mov a, r5

gdbu_1:

    cjne a, COUNTER, gdbu_1 ; wait for the interrupt
    setb P_GREEN ; LED on
    setb P_BLUE ; LED on

    mov dpl, r1
    mov dph, r2

    clr c
    mov a, dpl
    subb a, #0x01
    mov dpl, a
    mov a, dph
    subb a, #0x00
    mov dph, a

    clr a
    movc a, @a + dptr   ; low byte
    mov GREEN_PWM_L, a

    clr c
    mov a, dpl
    subb a, #0x01
    mov dpl, a
    mov a, dph
    subb a, #0x00
    mov dph, a

    clr a
    movc a, @a + dptr   ; high byte
    mov GREEN_PWM_H, a

    mov r1, dpl
    mov r2, dph

    mov dpl, r3
    mov dph, r4

    clr a
    movc a, @a + dptr   ; high byte
    mov BLUE_PWM_H, a
    inc dptr

    clr a
    movc a, @a + dptr   ; low byte
    mov BLUE_PWM_L, a
    inc dptr

    mov r3, dpl
    mov r4, dph

gdbu_2:

    mov a, r5
    cjne a, COUNTER, gdbu_3 ; Timer0 overflow
    mov a, TH0
    clr c
    subb a, GREEN_PWM_H   ; compare TH0 with GREEN_PWM_H
    jc gdbu_4 ; TH0 < GREEN_PWM_H, keep waiting
    jnz gdbu_3 ; TH0 > GREEN_PWM_H

    ; TH0 == GREEN_PWM_H, compare low byte
    mov  a, TL0
    clr  c
    subb a, GREEN_PWM_L
    jc gdbu_4 ; TL0 < GREEN_PWM_L, keep waiting

gdbu_3:

    clr P_GREEN ; LED off

gdbu_4:

    mov a, r5
    cjne a, COUNTER, gdbu_5 ; Timer0 overflow
    mov a, TH0
    clr c
    subb a, BLUE_PWM_H   ; compare TH0 with GREEN_PWM_H
    jc gdbu_2 ; TH0 < BLUE_PWM_H, keep waiting
    jnz gdbu_5 ; TH0 > BLUE_PWM_H

    ; TH0 == BLUE_PWM_H, compare low byte
    mov  a, TL0
    clr  c
    subb a, BLUE_PWM_L
    jc gdbu_2 ; TL0 < BLUE_PWM_L, keep waiting

gdbu_5:

    clr P_BLUE ; LED off

    mov a, r5
    cjne a, COUNTER, gdbu_6 ; Timer0 overflow
    sjmp gdbu_2

gdbu_6:

    djnz r7, gdbu_0
    djnz r6, gdbu_0

    ; RED UP
    setb P_BLUE

    mov dptr, #led_gamma_table

    mov r6, #0x04
    mov r7, #0xe8

red_up_0:

    inc r5
    mov a, r5

red_up_1:

    cjne a, COUNTER, red_up_1 ; wait for interrupt
    setb P_RED ; LED on

    clr a
    movc a, @a + dptr   ; high byte
    mov RED_PWM_H, a
    inc dptr

    clr a
    movc a, @a + dptr   ; low byte
    mov RED_PWM_L, a
    inc dptr

red_up_2:

    mov a, r5
    cjne a, COUNTER, red_up_3 ; Timer0 overflow
    mov a, TH0
    clr c
    subb a, RED_PWM_H   ; compare TH0 with RED_PWM_H
    jc red_up_2 ; TH0 < RED_PWM_H, keep waiting
    jnz red_up_3 ; TH0 > RED_PWM_H

    ; TH0 == RED_PWM_H, compare low byte
    mov  a, TL0
    clr  c
    subb a, RED_PWM_L
    jc red_up_2 ; TL0 < RED_PWM_L, keep waiting

red_up_3:

    clr P_RED ; LED off

    djnz r7, red_up_0
    djnz r6, red_up_0

    ; RED DOWN

    mov r6, #0x04
    mov r7, #0xe8

red_down_0:

    inc r5
    mov a, r5

red_down_1:

    cjne a, COUNTER, red_down_1 ; wait for the interrupt
    setb P_RED ; LED on

    clr c
    mov a, dpl
    subb a, #0x01
    mov dpl, a
    mov a, dph
    subb a, #0x00
    mov dph, a

    clr a
    movc a, @a + dptr   ; low byte
    mov RED_PWM_L, a

    clr c
    mov a, dpl
    subb a, #0x01
    mov dpl, a
    mov a, dph
    subb a, #0x00
    mov dph, a

    clr a
    movc a, @a + dptr   ; high byte
    mov RED_PWM_H, a

red_down_2:

    mov a, r5
    cjne a, COUNTER, red_down_3 ; Timer0 overflow
    mov a, TH0
    clr c
    subb a, RED_PWM_H   ; compare TH0 with RED_PWM_
    jc red_down_2 ; TH0 < RED_PWM_H, keep waiting
    jnz red_down_3 ; TH0 > RED_PWM_H

    ; TH0 == RED_PWM_H, compare low byte
    mov  a, TL0
    clr  c
    subb a, RED_PWM_L
    jc red_down_2 ; TL0 < RED_PWM_L, keep waiting

red_down_3:

    clr P_RED ; LED off

    djnz r7, red_down_0
    djnz r6, red_down_0

    ; GREEN UP, BLUE DOWN

    mov dptr, #led_gamma_table
    mov r1, dpl
    mov r2, dph

    mov dptr, #led_gamma_table_end
    mov r3, dpl
    mov r4, dph

    mov r6, #0x04
    mov r7, #0xe8

gubd_0:

    inc r5
    mov a, r5

gubd_1:

    cjne a, COUNTER, gubd_1 ; wait for the interrupt
    setb P_GREEN ; LED on
    setb P_BLUE ; LED on

    mov dpl, r1
    mov dph, r2

    clr a
    movc a, @a + dptr   ; high byte
    mov GREEN_PWM_H, a
    inc dptr

    clr a
    movc a, @a + dptr   ; low byte
    mov GREEN_PWM_L, a
    inc dptr

    mov r1, dpl
    mov r2, dph

    mov dpl, r3
    mov dph, r4

    clr c
    mov a, dpl
    subb a, #0x01
    mov dpl, a
    mov a, dph
    subb a, #0x00
    mov dph, a

    clr a
    movc a, @a + dptr   ; low byte
    mov BLUE_PWM_L, a

    clr c
    mov a, dpl
    subb a, #0x01
    mov dpl, a
    mov a, dph
    subb a, #0x00
    mov dph, a

    clr a
    movc a, @a + dptr   ; high byte
    mov BLUE_PWM_H, a

    mov r3, dpl
    mov r4, dph

gubd_2:

    mov a, r5
    cjne a, COUNTER, gubd_3 ; Timer0 overflow
    mov a, TH0
    clr c
    subb a, GREEN_PWM_H   ; compare TH0 with GREEN_PWM_H
    jc gubd_4 ; TH0 < GREEN_PWM_H, keep waiting
    jnz gubd_3 ; TH0 > GREEN_PWM_H

    ; TH0 == GREEN_PWM_H, compare low byte
    mov  a, TL0
    clr  c
    subb a, GREEN_PWM_L
    jc gubd_4 ; TL0 < GREEN_PWM_L, keep waiting

gubd_3:

    clr P_GREEN ; LED off

gubd_4:

    mov a, r5
    cjne a, COUNTER, gubd_5 ; Timer0 overflow
    mov a, TH0
    clr c
    subb a, BLUE_PWM_H   ; compare TH0 with BLUE_PWM_H
    jc gubd_2 ; TH0 < BLUE_PWM_H, keep waiting
    jnz gubd_5 ; TH0 > BLUE_PWM_H

    ; TH0 == BLUE_PWM_H, compare low byte
    mov  a, TL0
    clr  c
    subb a, BLUE_PWM_L
    jc gubd_2 ; TL0 < BLUE_PWM_L, keep waiting

gubd_5:

    clr P_BLUE ; LED off

    mov a, r5
    cjne a, COUNTER, gubd_6 ; Timer0 overflow
    sjmp gubd_2

gubd_6:

    djnz r7, gubd_0
    djnz r6, gubd_0

    ljmp flash_mode ; repeat dimming sequence

;-------------------------------------

load_modes:

    mov dptr, #store_addr

    clr a
    movc a, @a + dptr
    mov r0, a

    mov a, #0x01
    movc a, @a + dptr
    mov r1, a

    clr c
    mov a, r0
    subb a, #7
    jnc load_modes0

    mov LED_MODE, r0

load_modes0:

    clr c
    mov a, r1
    subb a, #2
    jnc load_modes1

    mov LAMP_MODE, r1

load_modes1:

    ret

;-------------------------------------

store_modes:

    push acc
    push psw

    mov r0, #ISP_BUFFER
    mov a, #32

store_modes0:

    mov @r0, #0xff
    inc r0
    dec a
    jnz store_modes0

    mov r0, #ISP_BUFFER
    mov a, LED_MODE
    mov @r0, a

    inc r0
    mov a, LAMP_MODE
    mov @r0, a

    mov PERAM, #ISP_BUFFER

    mov PEROMH, #>store_addr
    mov r0, #<store_addr
    ; Write PECMD[11:8] = 0x0a
    mov a, #0x0a
    orl a, R0
    mov PEROML, a

    ; Write PECMD[7:0] = 0x5A
    mov PECMD, #0x5a

    nop
    nop

    pop psw
    pop acc
    ret

led_gamma_table:
.dw  0xAE9F
.dw  0xAE9F
.dw  0xAE9F
.dw  0xAE9F
.dw  0xAE9F
.dw  0xAEA0
.dw  0xAEA0
.dw  0xAEA0
.dw  0xAEA0
.dw  0xAEA1
.dw  0xAEA1
.dw  0xAEA2
.dw  0xAEA2
.dw  0xAEA3
.dw  0xAEA3
.dw  0xAEA4
.dw  0xAEA4
.dw  0xAEA5
.dw  0xAEA6
.dw  0xAEA7
.dw  0xAEA7
.dw  0xAEA8
.dw  0xAEA9
.dw  0xAEAA
.dw  0xAEAB
.dw  0xAEAC
.dw  0xAEAD
.dw  0xAEAE
.dw  0xAEAF
.dw  0xAEB1
.dw  0xAEB2
.dw  0xAEB3
.dw  0xAEB4
.dw  0xAEB6
.dw  0xAEB7
.dw  0xAEB9
.dw  0xAEBA
.dw  0xAEBC
.dw  0xAEBD
.dw  0xAEBF
.dw  0xAEC0
.dw  0xAEC2
.dw  0xAEC4
.dw  0xAEC6
.dw  0xAEC7
.dw  0xAEC9
.dw  0xAECB
.dw  0xAECD
.dw  0xAECF
.dw  0xAED1
.dw  0xAED3
.dw  0xAED5
.dw  0xAED7
.dw  0xAEDA
.dw  0xAEDC
.dw  0xAEDE
.dw  0xAEE0
.dw  0xAEE3
.dw  0xAEE5
.dw  0xAEE8
.dw  0xAEEA
.dw  0xAEED
.dw  0xAEEF
.dw  0xAEF2
.dw  0xAEF4
.dw  0xAEF7
.dw  0xAEFA
.dw  0xAEFD
.dw  0xAF00
.dw  0xAF02
.dw  0xAF05
.dw  0xAF08
.dw  0xAF0B
.dw  0xAF0E
.dw  0xAF11
.dw  0xAF14
.dw  0xAF18
.dw  0xAF1B
.dw  0xAF1E
.dw  0xAF21
.dw  0xAF25
.dw  0xAF28
.dw  0xAF2B
.dw  0xAF2F
.dw  0xAF32
.dw  0xAF36
.dw  0xAF39
.dw  0xAF3D
.dw  0xAF41
.dw  0xAF44
.dw  0xAF48
.dw  0xAF4C
.dw  0xAF50
.dw  0xAF54
.dw  0xAF57
.dw  0xAF5B
.dw  0xAF5F
.dw  0xAF63
.dw  0xAF67
.dw  0xAF6C
.dw  0xAF70
.dw  0xAF74
.dw  0xAF78
.dw  0xAF7C
.dw  0xAF81
.dw  0xAF85
.dw  0xAF8A
.dw  0xAF8E
.dw  0xAF92
.dw  0xAF97
.dw  0xAF9C
.dw  0xAFA0
.dw  0xAFA5
.dw  0xAFAA
.dw  0xAFAE
.dw  0xAFB3
.dw  0xAFB8
.dw  0xAFBD
.dw  0xAFC2
.dw  0xAFC7
.dw  0xAFCC
.dw  0xAFD1
.dw  0xAFD6
.dw  0xAFDB
.dw  0xAFE0
.dw  0xAFE5
.dw  0xAFEA
.dw  0xAFF0
.dw  0xAFF5
.dw  0xAFFA
.dw  0xB000
.dw  0xB005
.dw  0xB00B
.dw  0xB010
.dw  0xB016
.dw  0xB01B
.dw  0xB021
.dw  0xB027
.dw  0xB02D
.dw  0xB032
.dw  0xB038
.dw  0xB03E
.dw  0xB044
.dw  0xB04A
.dw  0xB050
.dw  0xB056
.dw  0xB05C
.dw  0xB062
.dw  0xB068
.dw  0xB06E
.dw  0xB075
.dw  0xB07B
.dw  0xB081
.dw  0xB088
.dw  0xB08E
.dw  0xB094
.dw  0xB09B
.dw  0xB0A2
.dw  0xB0A8
.dw  0xB0AF
.dw  0xB0B5
.dw  0xB0BC
.dw  0xB0C3
.dw  0xB0CA
.dw  0xB0D0
.dw  0xB0D7
.dw  0xB0DE
.dw  0xB0E5
.dw  0xB0EC
.dw  0xB0F3
.dw  0xB0FA
.dw  0xB101
.dw  0xB109
.dw  0xB110
.dw  0xB117
.dw  0xB11E
.dw  0xB126
.dw  0xB12D
.dw  0xB134
.dw  0xB13C
.dw  0xB143
.dw  0xB14B
.dw  0xB152
.dw  0xB15A
.dw  0xB162
.dw  0xB169
.dw  0xB171
.dw  0xB179
.dw  0xB181
.dw  0xB189
.dw  0xB191
.dw  0xB198
.dw  0xB1A0
.dw  0xB1A9
.dw  0xB1B1
.dw  0xB1B9
.dw  0xB1C1
.dw  0xB1C9
.dw  0xB1D1
.dw  0xB1DA
.dw  0xB1E2
.dw  0xB1EA
.dw  0xB1F3
.dw  0xB1FB
.dw  0xB204
.dw  0xB20C
.dw  0xB215
.dw  0xB21D
.dw  0xB226
.dw  0xB22F
.dw  0xB238
.dw  0xB240
.dw  0xB249
.dw  0xB252
.dw  0xB25B
.dw  0xB264
.dw  0xB26D
.dw  0xB276
.dw  0xB27F
.dw  0xB288
.dw  0xB291
.dw  0xB29A
.dw  0xB2A4
.dw  0xB2AD
.dw  0xB2B6
.dw  0xB2C0
.dw  0xB2C9
.dw  0xB2D3
.dw  0xB2DC
.dw  0xB2E6
.dw  0xB2EF
.dw  0xB2F9
.dw  0xB303
.dw  0xB30C
.dw  0xB316
.dw  0xB320
.dw  0xB32A
.dw  0xB333
.dw  0xB33D
.dw  0xB347
.dw  0xB351
.dw  0xB35B
.dw  0xB365
.dw  0xB370
.dw  0xB37A
.dw  0xB384
.dw  0xB38E
.dw  0xB398
.dw  0xB3A3
.dw  0xB3AD
.dw  0xB3B8
.dw  0xB3C2
.dw  0xB3CD
.dw  0xB3D7
.dw  0xB3E2
.dw  0xB3EC
.dw  0xB3F7
.dw  0xB402
.dw  0xB40C
.dw  0xB417
.dw  0xB422
.dw  0xB42D
.dw  0xB438
.dw  0xB443
.dw  0xB44E
.dw  0xB459
.dw  0xB464
.dw  0xB46F
.dw  0xB47A
.dw  0xB485
.dw  0xB491
.dw  0xB49C
.dw  0xB4A7
.dw  0xB4B3
.dw  0xB4BE
.dw  0xB4CA
.dw  0xB4D5
.dw  0xB4E1
.dw  0xB4EC
.dw  0xB4F8
.dw  0xB504
.dw  0xB50F
.dw  0xB51B
.dw  0xB527
.dw  0xB533
.dw  0xB53E
.dw  0xB54A
.dw  0xB556
.dw  0xB562
.dw  0xB56E
.dw  0xB57A
.dw  0xB587
.dw  0xB593
.dw  0xB59F
.dw  0xB5AB
.dw  0xB5B8
.dw  0xB5C4
.dw  0xB5D0
.dw  0xB5DD
.dw  0xB5E9
.dw  0xB5F6
.dw  0xB602
.dw  0xB60F
.dw  0xB61B
.dw  0xB628
.dw  0xB635
.dw  0xB642
.dw  0xB64E
.dw  0xB65B
.dw  0xB668
.dw  0xB675
.dw  0xB682
.dw  0xB68F
.dw  0xB69C
.dw  0xB6A9
.dw  0xB6B6
.dw  0xB6C3
.dw  0xB6D1
.dw  0xB6DE
.dw  0xB6EB
.dw  0xB6F8
.dw  0xB706
.dw  0xB713
.dw  0xB721
.dw  0xB72E
.dw  0xB73C
.dw  0xB749
.dw  0xB757
.dw  0xB765
.dw  0xB772
.dw  0xB780
.dw  0xB78E
.dw  0xB79C
.dw  0xB7AA
.dw  0xB7B8
.dw  0xB7C6
.dw  0xB7D4
.dw  0xB7E2
.dw  0xB7F0
.dw  0xB7FE
.dw  0xB80C
.dw  0xB81A
.dw  0xB828
.dw  0xB837
.dw  0xB845
.dw  0xB853
.dw  0xB862
.dw  0xB870
.dw  0xB87F
.dw  0xB88D
.dw  0xB89C
.dw  0xB8AB
.dw  0xB8B9
.dw  0xB8C8
.dw  0xB8D7
.dw  0xB8E6
.dw  0xB8F4
.dw  0xB903
.dw  0xB912
.dw  0xB921
.dw  0xB930
.dw  0xB93F
.dw  0xB94E
.dw  0xB95E
.dw  0xB96D
.dw  0xB97C
.dw  0xB98B
.dw  0xB99A
.dw  0xB9AA
.dw  0xB9B9
.dw  0xB9C9
.dw  0xB9D8
.dw  0xB9E8
.dw  0xB9F7
.dw  0xBA07
.dw  0xBA16
.dw  0xBA26
.dw  0xBA36
.dw  0xBA46
.dw  0xBA55
.dw  0xBA65
.dw  0xBA75
.dw  0xBA85
.dw  0xBA95
.dw  0xBAA5
.dw  0xBAB5
.dw  0xBAC5
.dw  0xBAD5
.dw  0xBAE5
.dw  0xBAF6
.dw  0xBB06
.dw  0xBB16
.dw  0xBB27
.dw  0xBB37
.dw  0xBB47
.dw  0xBB58
.dw  0xBB68
.dw  0xBB79
.dw  0xBB89
.dw  0xBB9A
.dw  0xBBAB
.dw  0xBBBC
.dw  0xBBCC
.dw  0xBBDD
.dw  0xBBEE
.dw  0xBBFF
.dw  0xBC10
.dw  0xBC21
.dw  0xBC32
.dw  0xBC43
.dw  0xBC54
.dw  0xBC65
.dw  0xBC76
.dw  0xBC87
.dw  0xBC99
.dw  0xBCAA
.dw  0xBCBB
.dw  0xBCCD
.dw  0xBCDE
.dw  0xBCF0
.dw  0xBD01
.dw  0xBD13
.dw  0xBD24
.dw  0xBD36
.dw  0xBD48
.dw  0xBD59
.dw  0xBD6B
.dw  0xBD7D
.dw  0xBD8F
.dw  0xBDA1
.dw  0xBDB3
.dw  0xBDC5
.dw  0xBDD7
.dw  0xBDE9
.dw  0xBDFB
.dw  0xBE0D
.dw  0xBE1F
.dw  0xBE31
.dw  0xBE43
.dw  0xBE56
.dw  0xBE68
.dw  0xBE7B
.dw  0xBE8D
.dw  0xBE9F
.dw  0xBEB2
.dw  0xBEC5
.dw  0xBED7
.dw  0xBEEA
.dw  0xBEFC
.dw  0xBF0F
.dw  0xBF22
.dw  0xBF35
.dw  0xBF48
.dw  0xBF5A
.dw  0xBF6D
.dw  0xBF80
.dw  0xBF93
.dw  0xBFA6
.dw  0xBFBA
.dw  0xBFCD
.dw  0xBFE0
.dw  0xBFF3
.dw  0xC006
.dw  0xC01A
.dw  0xC02D
.dw  0xC040
.dw  0xC054
.dw  0xC067
.dw  0xC07B
.dw  0xC08E
.dw  0xC0A2
.dw  0xC0B6
.dw  0xC0C9
.dw  0xC0DD
.dw  0xC0F1
.dw  0xC105
.dw  0xC118
.dw  0xC12C
.dw  0xC140
.dw  0xC154
.dw  0xC168
.dw  0xC17C
.dw  0xC190
.dw  0xC1A5
.dw  0xC1B9
.dw  0xC1CD
.dw  0xC1E1
.dw  0xC1F6
.dw  0xC20A
.dw  0xC21E
.dw  0xC233
.dw  0xC247
.dw  0xC25C
.dw  0xC270
.dw  0xC285
.dw  0xC29A
.dw  0xC2AE
.dw  0xC2C3
.dw  0xC2D8
.dw  0xC2ED
.dw  0xC301
.dw  0xC316
.dw  0xC32B
.dw  0xC340
.dw  0xC355
.dw  0xC36A
.dw  0xC37F
.dw  0xC395
.dw  0xC3AA
.dw  0xC3BF
.dw  0xC3D4
.dw  0xC3EA
.dw  0xC3FF
.dw  0xC414
.dw  0xC42A
.dw  0xC43F
.dw  0xC455
.dw  0xC46A
.dw  0xC480
.dw  0xC496
.dw  0xC4AB
.dw  0xC4C1
.dw  0xC4D7
.dw  0xC4ED
.dw  0xC502
.dw  0xC518
.dw  0xC52E
.dw  0xC544
.dw  0xC55A
.dw  0xC570
.dw  0xC586
.dw  0xC59D
.dw  0xC5B3
.dw  0xC5C9
.dw  0xC5DF
.dw  0xC5F6
.dw  0xC60C
.dw  0xC622
.dw  0xC639
.dw  0xC64F
.dw  0xC666
.dw  0xC67C
.dw  0xC693
.dw  0xC6AA
.dw  0xC6C0
.dw  0xC6D7
.dw  0xC6EE
.dw  0xC705
.dw  0xC71B
.dw  0xC732
.dw  0xC749
.dw  0xC760
.dw  0xC777
.dw  0xC78E
.dw  0xC7A5
.dw  0xC7BD
.dw  0xC7D4
.dw  0xC7EB
.dw  0xC802
.dw  0xC81A
.dw  0xC831
.dw  0xC848
.dw  0xC860
.dw  0xC877
.dw  0xC88F
.dw  0xC8A6
.dw  0xC8BE
.dw  0xC8D6
.dw  0xC8ED
.dw  0xC905
.dw  0xC91D
.dw  0xC935
.dw  0xC94D
.dw  0xC964
.dw  0xC97C
.dw  0xC994
.dw  0xC9AC
.dw  0xC9C4
.dw  0xC9DD
.dw  0xC9F5
.dw  0xCA0D
.dw  0xCA25
.dw  0xCA3D
.dw  0xCA56
.dw  0xCA6E
.dw  0xCA87
.dw  0xCA9F
.dw  0xCAB7
.dw  0xCAD0
.dw  0xCAE9
.dw  0xCB01
.dw  0xCB1A
.dw  0xCB32
.dw  0xCB4B
.dw  0xCB64
.dw  0xCB7D
.dw  0xCB96
.dw  0xCBAF
.dw  0xCBC8
.dw  0xCBE1
.dw  0xCBFA
.dw  0xCC13
.dw  0xCC2C
.dw  0xCC45
.dw  0xCC5E
.dw  0xCC77
.dw  0xCC91
.dw  0xCCAA
.dw  0xCCC3
.dw  0xCCDD
.dw  0xCCF6
.dw  0xCD10
.dw  0xCD29
.dw  0xCD43
.dw  0xCD5C
.dw  0xCD76
.dw  0xCD90
.dw  0xCDA9
.dw  0xCDC3
.dw  0xCDDD
.dw  0xCDF7
.dw  0xCE11
.dw  0xCE2B
.dw  0xCE45
.dw  0xCE5F
.dw  0xCE79
.dw  0xCE93
.dw  0xCEAD
.dw  0xCEC7
.dw  0xCEE2
.dw  0xCEFC
.dw  0xCF16
.dw  0xCF30
.dw  0xCF4B
.dw  0xCF65
.dw  0xCF80
.dw  0xCF9A
.dw  0xCFB5
.dw  0xCFD0
.dw  0xCFEA
.dw  0xD005
.dw  0xD020
.dw  0xD03A
.dw  0xD055
.dw  0xD070
.dw  0xD08B
.dw  0xD0A6
.dw  0xD0C1
.dw  0xD0DC
.dw  0xD0F7
.dw  0xD112
.dw  0xD12D
.dw  0xD149
.dw  0xD164
.dw  0xD17F
.dw  0xD19A
.dw  0xD1B6
.dw  0xD1D1
.dw  0xD1ED
.dw  0xD208
.dw  0xD224
.dw  0xD23F
.dw  0xD25B
.dw  0xD276
.dw  0xD292
.dw  0xD2AE
.dw  0xD2CA
.dw  0xD2E5
.dw  0xD301
.dw  0xD31D
.dw  0xD339
.dw  0xD355
.dw  0xD371
.dw  0xD38D
.dw  0xD3A9
.dw  0xD3C6
.dw  0xD3E2
.dw  0xD3FE
.dw  0xD41A
.dw  0xD437
.dw  0xD453
.dw  0xD46F
.dw  0xD48C
.dw  0xD4A8
.dw  0xD4C5
.dw  0xD4E1
.dw  0xD4FE
.dw  0xD51B
.dw  0xD537
.dw  0xD554
.dw  0xD571
.dw  0xD58E
.dw  0xD5AB
.dw  0xD5C8
.dw  0xD5E5
.dw  0xD602
.dw  0xD61F
.dw  0xD63C
.dw  0xD659
.dw  0xD676
.dw  0xD693
.dw  0xD6B0
.dw  0xD6CE
.dw  0xD6EB
.dw  0xD708
.dw  0xD726
.dw  0xD743
.dw  0xD761
.dw  0xD77E
.dw  0xD79C
.dw  0xD7B9
.dw  0xD7D7
.dw  0xD7F5
.dw  0xD813
.dw  0xD830
.dw  0xD84E
.dw  0xD86C
.dw  0xD88A
.dw  0xD8A8
.dw  0xD8C6
.dw  0xD8E4
.dw  0xD902
.dw  0xD920
.dw  0xD93E
.dw  0xD95D
.dw  0xD97B
.dw  0xD999
.dw  0xD9B7
.dw  0xD9D6
.dw  0xD9F4
.dw  0xDA13
.dw  0xDA31
.dw  0xDA50
.dw  0xDA6E
.dw  0xDA8D
.dw  0xDAAC
.dw  0xDACA
.dw  0xDAE9
.dw  0xDB08
.dw  0xDB27
.dw  0xDB45
.dw  0xDB64
.dw  0xDB83
.dw  0xDBA2
.dw  0xDBC1
.dw  0xDBE0
.dw  0xDC00
.dw  0xDC1F
.dw  0xDC3E
.dw  0xDC5D
.dw  0xDC7C
.dw  0xDC9C
.dw  0xDCBB
.dw  0xDCDB
.dw  0xDCFA
.dw  0xDD1A
.dw  0xDD39
.dw  0xDD59
.dw  0xDD78
.dw  0xDD98
.dw  0xDDB8
.dw  0xDDD7
.dw  0xDDF7
.dw  0xDE17
.dw  0xDE37
.dw  0xDE57
.dw  0xDE77
.dw  0xDE97
.dw  0xDEB7
.dw  0xDED7
.dw  0xDEF7
.dw  0xDF17
.dw  0xDF37
.dw  0xDF58
.dw  0xDF78
.dw  0xDF98
.dw  0xDFB9
.dw  0xDFD9
.dw  0xDFFA
.dw  0xE01A
.dw  0xE03B
.dw  0xE05B
.dw  0xE07C
.dw  0xE09C
.dw  0xE0BD
.dw  0xE0DE
.dw  0xE0FF
.dw  0xE120
.dw  0xE140
.dw  0xE161
.dw  0xE182
.dw  0xE1A3
.dw  0xE1C4
.dw  0xE1E5
.dw  0xE207
.dw  0xE228
.dw  0xE249
.dw  0xE26A
.dw  0xE28B
.dw  0xE2AD
.dw  0xE2CE
.dw  0xE2F0
.dw  0xE311
.dw  0xE333
.dw  0xE354
.dw  0xE376
.dw  0xE397
.dw  0xE3B9
.dw  0xE3DB
.dw  0xE3FC
.dw  0xE41E
.dw  0xE440
.dw  0xE462
.dw  0xE484
.dw  0xE4A6
.dw  0xE4C8
.dw  0xE4EA
.dw  0xE50C
.dw  0xE52E
.dw  0xE550
.dw  0xE572
.dw  0xE595
.dw  0xE5B7
.dw  0xE5D9
.dw  0xE5FC
.dw  0xE61E
.dw  0xE641
.dw  0xE663
.dw  0xE686
.dw  0xE6A8
.dw  0xE6CB
.dw  0xE6EE
.dw  0xE710
.dw  0xE733
.dw  0xE756
.dw  0xE779
.dw  0xE79C
.dw  0xE7BE
.dw  0xE7E1
.dw  0xE804
.dw  0xE828
.dw  0xE84B
.dw  0xE86E
.dw  0xE891
.dw  0xE8B4
.dw  0xE8D7
.dw  0xE8FB
.dw  0xE91E
.dw  0xE941
.dw  0xE965
.dw  0xE988
.dw  0xE9AC
.dw  0xE9CF
.dw  0xE9F3
.dw  0xEA17
.dw  0xEA3A
.dw  0xEA5E
.dw  0xEA82
.dw  0xEAA5
.dw  0xEAC9
.dw  0xEAED
.dw  0xEB11
.dw  0xEB35
.dw  0xEB59
.dw  0xEB7D
.dw  0xEBA1
.dw  0xEBC5
.dw  0xEBEA
.dw  0xEC0E
.dw  0xEC32
.dw  0xEC56
.dw  0xEC7B
.dw  0xEC9F
.dw  0xECC3
.dw  0xECE8
.dw  0xED0C
.dw  0xED31
.dw  0xED56
.dw  0xED7A
.dw  0xED9F
.dw  0xEDC4
.dw  0xEDE8
.dw  0xEE0D
.dw  0xEE32
.dw  0xEE57
.dw  0xEE7C
.dw  0xEEA1
.dw  0xEEC6
.dw  0xEEEB
.dw  0xEF10
.dw  0xEF35
.dw  0xEF5A
.dw  0xEF7F
.dw  0xEFA5
.dw  0xEFCA
.dw  0xEFEF
.dw  0xF015
.dw  0xF03A
.dw  0xF060
.dw  0xF085
.dw  0xF0AB
.dw  0xF0D0
.dw  0xF0F6
.dw  0xF11C
.dw  0xF141
.dw  0xF167
.dw  0xF18D
.dw  0xF1B3
.dw  0xF1D9
.dw  0xF1FF
.dw  0xF225
.dw  0xF24B
.dw  0xF271
.dw  0xF297
.dw  0xF2BD
.dw  0xF2E3
.dw  0xF309
.dw  0xF32F
.dw  0xF356
.dw  0xF37C
.dw  0xF3A3
.dw  0xF3C9
.dw  0xF3EF
.dw  0xF416
.dw  0xF43C
.dw  0xF463
.dw  0xF48A
.dw  0xF4B0
.dw  0xF4D7
.dw  0xF4FE
.dw  0xF525
.dw  0xF54C
.dw  0xF572
.dw  0xF599
.dw  0xF5C0
.dw  0xF5E7
.dw  0xF60E
.dw  0xF635
.dw  0xF65D
.dw  0xF684
.dw  0xF6AB
.dw  0xF6D2
.dw  0xF6FA
.dw  0xF721
.dw  0xF748
.dw  0xF770
.dw  0xF797
.dw  0xF7BF
.dw  0xF7E6
.dw  0xF80E
.dw  0xF836
.dw  0xF85D
.dw  0xF885
.dw  0xF8AD
.dw  0xF8D5
.dw  0xF8FC
.dw  0xF924
.dw  0xF94C
.dw  0xF974
.dw  0xF99C
.dw  0xF9C4
.dw  0xF9EC
.dw  0xFA14
.dw  0xFA3D
.dw  0xFA65
.dw  0xFA8D
.dw  0xFAB5
.dw  0xFADE
.dw  0xFB06
.dw  0xFB2F
.dw  0xFB57
.dw  0xFB80
.dw  0xFBA8
.dw  0xFBD1
.dw  0xFBF9
.dw  0xFC22
.dw  0xFC4B
.dw  0xFC74
.dw  0xFC9C
.dw  0xFCC5
.dw  0xFCEE
.dw  0xFD17
.dw  0xFD40
.dw  0xFD69
.dw  0xFD92
.dw  0xFDBB
.dw  0xFDE4
.dw  0xFE0E
.dw  0xFE37
.dw  0xFE60
.dw  0xFE89
.dw  0xFEB3
.dw  0xFEDC
.dw  0xFF06
.dw  0xFF2F
.dw  0xFF59
.dw  0xFF82
.dw  0xFFAC
.dw  0xFFD5
.dw  0xFFFF

led_gamma_table_end:
