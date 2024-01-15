;===============================================================================
	.title	Aurora 9x18 mk2
;
;		by Akimitsu Sadoi - www.theLEDart.com
;-------------------------------------------------------------------------------
;	Version history
;	1.0	ported from PIC24FV16KA304 version (4/6/2012)
;	1.2 universal source code for Aurora 9x18 mk2 and 18x18
;===============================================================================

	.include "P24FV16KA301.INC"
	.list	b=4
	.include "SONY_TV.INC"	; Sony TV remote codes

;===============================================================================
;	constants
;
	.global __reset
	.global __T2Interrupt				; Timer2 ISR entry
	.global __T5Interrupt				; Timer5 ISR entry - auto-shutoff
	.global __CNInterrupt				; IR (CN) ISR entry
;-------------------------------------------------------------------------------
;
	.equ	osc_adjust,	0				; value to calibrate internal oscillator (-32 ~ +31)

	.equ	speed_step,0x8000/8			; speed adjust step value
	.equ	speed_norm,0x7FFE			; speed adjust center/normal value

	.equ	max_bor, 10					; maximum number of BOR allowed in series

	.equ	num_modes,(mode_tbl_end-mode_tbl)/2

	;--- auto-shutoff timer setting ------------------------
	.equ	shutoff_time, 0				; shutoff time in minutes (max:1,145 (about 19 Hours))
.if (shutoff_time != 0)
	.equ	timer_ticks, (shutoff_time*3750000)
	.equ	TIMER4_VAL, (timer_ticks & 0xFFFF)
	.equ	TIMER5_VAL, (timer_ticks / 0x10000)
	.equ	T4CON_VAL, ((1<<TON)+(1<<TCKPS1)+(1<<TCKPS0)+(1<<T32))
.endif
	;--- PWM timing parameters -----------------------------
	; LED refresh time = (pr_value+1)*(3*127+1)*Tcy = (pr_value+1)*382*Tcy
	;   optimized for video @225 Hz

	.equ	max_duty, 0xFF				; duty cycle value for 100% duty (8 bit)
	.equ	port_delay,	42				; delay time (in Tcy) between timer INT and port set (compensates for LED/Column drivers' fall time)
	.equ	port_delay_comp, 0			; pulse rinse time compensation value
	.equ	port_blank, 68				; blank period before start of the pulse (compensates for RGB drivers' fall time)
	.equ	pr_value, 186

	; Output Compare - double compare single-shot mode, system clock
	.equ	OCCON_VAL,(1<<OCM2+1<<OCTSEL0+1<<OCTSEL1+1<<OCTSEL2)
	; Output Compare - inverted output, sync to timer 2
	.equ	OCCON2_VAL,(1<<12+1<<SYNCSEL2+1<<SYNCSEL3)

	;--- switch parameters ---------------------------------
	.equ	debounce_time, 16			; (up to 16) x 2.048 mS
	.equ	debounce_bits, (1<<debounce_time-1)
	.equ	long_push_time, 240			; x 2.048 mS

	;--- IR receiver parameters ----------------------------
	.equ	start_bit,		2000*16		; minimum duration of start bit (in micro second)
	.equ	bit_threshold,	900*16		; threshold value used to determin the bit value(long/short pulse)(in micro second)
	.equ	accept_dev,	device_sony_tv
	.equ	IR_timeout_pr,	500/2		; timeout period for key repeat (in milliseconds)

	;--- port & pin mapping for I/O ----------------------------------

	; switch 1 is connected to RA0/CN2
	.equ	SW1_PORT, PORTA
	.equ	SW1_TRIS, TRISA
	.equ	SW1_ANS, ANSELA				; analog select - not ANSx as the manual states
	.equ	SW1_BIT, 0
	.equ	SW1_CN, 2
	; IR receiver is connected to RB15/CN11
	.equ	IR_PORT, PORTB
	.equ	IR_TRIS, TRISB
	.equ	IR_ANS, ANSELB				; analog select - not ANSx as the manual states
	.equ	IR_BIT, 15
	.equ	IR_CN, 11
	; analog input - RB14/AN10/CN12
	.equ	AN_IN_PORT, PORTB
	.equ	AN_IN_TRIS, TRISB
	.equ	AN_ANS, ANSELB				; analog select - not ANSx as the manual states
	.equ	AN_IN_BIT, 14
	.equ	AN_IN_CN, 12
	.equ	AN_IN_APIN, 10				; analog input #

.ifdef __DEBUG
	.equ	_debug_tris,TRISA
	.equ	_debug_port,LATA
	.equ	_debug_out,1
.endif

	;--- COL & ROW drive parameters ------------------------
	.equ	COL_POL, 1					; 0:active-low 1:active-high
	.equ	ROW_POL, 0					; 0:active-low 1:active-high
	
	.equ	num_COLs, 9					; number of COLs
	.equ	num_ROWs, 1					; number of RGB ROWs
	.equ	num_LEDs, num_COLs*num_ROWs	; number of LEDs

	;--- LEDs ----------------------------------------------
	.equ	LED_1_PORT,_RA_
	.equ	LED_1_PIN,3

	.equ	LED_2_PORT,_RA_
	.equ	LED_2_PIN,2

	.equ	LED_3_PORT,_RB_
	.equ	LED_3_PIN,2

	.equ	LED_4_PORT,_RB_
	.equ	LED_4_PIN,13

	.equ	LED_5_PORT,_RB_
	.equ	LED_5_PIN,12

	.equ	LED_6_PORT,_RB_
	.equ	LED_6_PIN,9

	.equ	LED_7_PORT,_RB_
	.equ	LED_7_PIN,8

	.equ	LED_8_PORT,_RA_
	.equ	LED_8_PIN,4

	.equ	LED_9_PORT,_RB_
	.equ	LED_9_PIN,4

	.equ	PORTA_bits, 5				; highest port # used + 1
	.equ	PORTB_bits, 16
	.equ	PORTC_bits, 0

	;--- PWM R/G/B ports ---
	.equ	PWM_R_LAT,LATB
	.equ	PWM_R_PIN,7		; OC1/RB7
	.equ	PWM_R_OC,OC1RS
	.equ	PWM_R_OCC,OC1CON1

	.equ	PWM_G_LAT,LATB
	.equ	PWM_G_PIN,1		; OC3/RB1
	.equ	PWM_G_OC,OC3RS
	.equ	PWM_G_OCC,OC3CON1

	.equ	PWM_B_LAT,LATB
	.equ	PWM_B_PIN,0		; OC2/RB0
	.equ	PWM_B_OC,OC2RS
	.equ	PWM_B_OCC,OC2CON1

	.equ	_RA_,0
	.equ	_RB_,(PORTA_bits*2)
	.equ	_RC_,((PORTA_bits+PORTB_bits)*2)

	.text
	;--- LED data -> duty_buff offset lookup table ---------
LED_pins:
	.byte	LED_1_PIN*2+LED_1_PORT
	.byte	LED_2_PIN*2+LED_2_PORT
	.byte	LED_3_PIN*2+LED_3_PORT
	.byte	LED_4_PIN*2+LED_4_PORT
	.byte	LED_5_PIN*2+LED_5_PORT
	.byte	LED_6_PIN*2+LED_6_PORT
	.byte	LED_7_PIN*2+LED_7_PORT
	.byte	LED_8_PIN*2+LED_8_PORT
	.byte	LED_9_PIN*2+LED_9_PORT

;===============================================================================

	.include "aurora_main.s"	; Aurora main codes

;===============================================================================

	.end
