/*-
 * "THE BEER-WARE LICENSE" (Revision 42):
 * Philip Schulz <phs@phisch.org> wrote this file. As long as you retain this
 * notice you can do whatever you want with this stuff. If we meet some day,
 * and you think this stuff is worth it, you can buy me a beer in return.
 */ 

#include <avr/io.h>
#include <avr/interrupt.h>
#include <stdlib.h>
#include <string.h>

#define assert(_eq) if (!(_eq)) panic()

/******************************************************************************
 * Data Structures
 *****************************************************************************/
enum mode_e {
    e_off       = 0,
	e_min       = 1,
    e_slow      = 2,
	e_fast      = 3,
    e_max       = 4,
    e_random    = 5,
	e_maxmode   = 6
};

typedef enum mode_e mode_t;

/*
 *
 * This is the meaning of the random game modes:
 *
 *   e_const    -- Keep current speed.
 *   e_inc      -- Increment speed (linear)
 *   e_dec      -- Decrement speed (linear)
 *   e_mul      -- Multiply speed (by positive percentage)
 *   e_div      -- Multiply speed (by negative percentage)
 */
enum randommode_e {
    e_const     = 0,
    e_inc       = 1,
    e_dec       = 2,
/*
    e_mul       = 3,
    e_div       = 4,
*/
    e_jmp       = 3,
    e_maxrnd    = 4
};

typedef enum randommode_e randommode_t;

struct looping_louie_s {
    /*
     * The PWM timer T0 is used to count from 0 to m_maxpwm and back. It
     * toggles the output pin when the threshold g_pwmval is crossed. Hence,
     * m_curpwm divided by m_maxpwm is the relative output value.
     */
    int     m_maxpwm;
    int     m_curpwm;
    int     m_pwm;
    int     m_minpwm;

    /*
     * Timer T1 is used to decrement m_curdelay with a frequency of 2 Hz. The
     * main program is written such that if m_curdelay reaches 0, an update of
     * the game is performed and m_updmod is decremented by 1. When an update
     * has been performed, m_curdelay is reset back to m_delay.
     *
     * Also, the value of the PWM (m_curpwm) is adjusted, depending on the game
     * mode, when m_curdelay reaches 0.
     *
     * When m_updmod reaches 0, m_delay is reset to a random value between 1
     * and m_maxdelay.
     */
    int     m_mindelay;
    int     m_curdelay;
    int     m_delay;
    int     m_maxdelay;

    /*
     * The variable m_updmod is decremented whenever m_curdelay reaches 0. When
     * m_updmod reaches 0, a new game mode is chosen from the enum randommode_e
     * above. When the game mode is updated, the m_updmod is set to a value
     * between 1 and  m_maxupdmod, effectively setting the time for how long the
     * game operates in the current mode.
     */
    int     m_minupdmod;
    int     m_updmod;
    int     m_maxupdmod;
    
    /*
     * Determines how much m_pwm is changed when m_curdelay reaches 0.
     */
    int     m_minchange;
    int     m_change;
    int     m_maxchange;
    
    randommode_t  m_mode;
};

typedef struct looping_louie_s looping_louie_t;

static looping_louie_t *g_status;

struct button_s {
	#define BTN_STATUS_NUMBER       0x7;
	#define BTN_STATUS_CURSAMPLE    (1 << 3)
	#define BTN_STATUS_PREVSAMPLE   (1 << 4)
	#define BTN_STATUS_POSEDGE      (1 << 5)
	#define BTN_STATUS_NEGEDGE      (1 << 6)
	#define BTN_STATUS_VALUE        (1 << 7)
	uint8_t m_status;
	
    uint8_t m_count;
	uint8_t m_threshold;
};

typedef struct button_s button_t;

/******************************************************************************
 * Prototypes
 *****************************************************************************/
static void     ll_init(looping_louie_t *p_ll);
static mode_t   ll_getnextmode(mode_t p_mode);
static void     ll_playrandom(looping_louie_t *p_ll);

static void     btn_init(button_t *p_btn, uint8_t p_number, uint8_t p_threshold);
static void     btn_eval(button_t *p_btn);

static void     setup_platform(void);
static void     setup_t0(void);
static void     setup_t1(void);
static void     setup_portb(void);

static int      constrained_rand(int p_lo, int p_hi);
static void     panic(void);

/******************************************************************************
 * Main Program
 *****************************************************************************/
int
main(void) {
    looping_louie_t status;
    mode_t          mode = e_off;
    button_t        btn;

    ll_init(&status);
    btn_init(&btn, 4, 25);
	
    setup_platform();

    assert(!(btn.m_status & BTN_STATUS_POSEDGE));
    assert(!(btn.m_status & BTN_STATUS_VALUE));

    while(1) {
		btn_eval(&btn);
		
		if (btn.m_status & BTN_STATUS_POSEDGE) {
            mode = ll_getnextmode(mode);
			if (mode != e_off) {
                DDRB  &= ~ _BV(PINB3);
			    PORTB &= ~ _BV(PINB4);
			} else {
                DDRB  |= _BV(PINB3);
			    PORTB |= _BV(PINB4);
			}
		}

        if (mode != e_random) {
            status.m_delay  = status.m_mindelay;
            status.m_updmod = status.m_minupdmod;
            status.m_mode   = e_const;
        }		

        switch (mode) {
        case e_off:
            status.m_pwm = 0;
            break;
		case e_min:
		    status.m_pwm = status.m_minpwm;
		    break;
        case e_slow:
			status.m_pwm = 96;
            break;
		case e_fast:
		    status.m_pwm = 128;
			break;
		case e_max:
            status.m_pwm = status.m_maxpwm;
            break;
        case e_random:
            ll_playrandom(&status);
            break;
		case e_maxmode:
		    /* NOTREACHED */
		    panic();
			break;
        }

        cli();
        if (status.m_curdelay == 0) {
            status.m_curdelay   = status.m_delay;
            status.m_curpwm     = status.m_pwm;

            OCR0B = g_status->m_curpwm;
        }
        sei();
    }

    /* NOTREACHED */
    panic();
     return (0);
}

/******************************************************************************
 * Set up initial values of Game Status
 *****************************************************************************/
static void
ll_init(looping_louie_t *p_ll) {
    memset(p_ll, 0, sizeof(*p_ll));
    
    p_ll->m_mindelay    = 1;
    p_ll->m_curdelay    = 2;
    p_ll->m_delay       = 2;
    p_ll->m_maxdelay    = 5;
    
    p_ll->m_minupdmod   = 2;
    p_ll->m_updmod      = 2;
    p_ll->m_maxupdmod   = 3;
    
    p_ll->m_minpwm      = 75;
    p_ll->m_curpwm      = p_ll->m_minpwm;
    p_ll->m_pwm         = p_ll->m_curpwm;
    p_ll->m_maxpwm      = 150; // 176;
    
    g_status = p_ll;
}

/******************************************************************************
 *
 *****************************************************************************/
static mode_t
ll_getnextmode(mode_t p_mode) {
    mode_t mode = p_mode;

	mode = (mode_t) ((p_mode + 1) % (e_maxmode));
	if (mode == e_off)
	    mode = (mode_t) ((mode + 1) % (e_maxmode));;
		
	assert(mode > e_off);
	assert(mode < e_maxmode);
	assert(p_mode != mode);
	
    return mode;
}

/******************************************************************************
 *
 *****************************************************************************/
static void
ll_playrandom(looping_louie_t *p_ll) {
    cli();
    if (p_ll->m_curdelay != 0) {
        sei();
        return;
    }
    sei();

    switch (p_ll->m_mode) {
    case e_const:
        /* m_pwm stays the same. */
        break;
    case e_inc:
        if ((p_ll->m_maxpwm - p_ll->m_change) <= p_ll->m_pwm) {
            p_ll->m_pwm = p_ll->m_maxpwm;
        } else {
            p_ll->m_pwm += p_ll->m_change;
        }                
        break;
    case e_dec:
        if ((p_ll->m_minpwm + p_ll->m_change) <= p_ll->m_pwm) {
            p_ll->m_pwm = p_ll->m_minpwm;
        } else {
            p_ll->m_pwm -= p_ll->m_change;
        }
        break;
/*
    case e_mul:
        if ((p_ll->m_pwm & 0x80)) {
			p_ll->m_pwm = p_ll->m_maxpwm;
		} else {
		    p_ll->m_pwm = p_ll->m_pwm << 1;	
		}
		break;
    case e_div:
        if (p_ll->m_pwm) {
		    p_ll->m_pwm = (p_ll->m_pwm >> 1) & (p_ll->m_pwm - 1);
		} else {
			p_ll->m_pwm = p_ll->m_minpwm;
		}
        break;
*/
    case e_jmp:
        p_ll->m_pwm = constrained_rand(p_ll->m_minpwm, p_ll->m_maxpwm);
        break;
    case e_maxrnd:
        /* NOTREACHED */
        panic();
        break;
    }

	if (p_ll->m_pwm > p_ll->m_maxpwm)
		p_ll->m_pwm = p_ll->m_maxpwm;
			
	if (p_ll->m_pwm < p_ll->m_minpwm)
		p_ll->m_pwm = p_ll->m_minpwm;

    if (p_ll->m_updmod == 0) {
        p_ll->m_delay  = constrained_rand(p_ll->m_mindelay, p_ll->m_maxdelay);
        p_ll->m_updmod = constrained_rand(p_ll->m_minupdmod, p_ll->m_maxupdmod);
        p_ll->m_mode   = (randommode_t) constrained_rand(0, e_maxrnd);
    } else {
        p_ll->m_updmod--;
    }
}

/******************************************************************************
 *
 *****************************************************************************/
static void
setup_platform(void) {
    /* Disable the Analog/Digital Converter */
    ACSR = _BV(ACD);

    setup_portb();

    /* Stop timers during configuration */
    GTCCR   |= _BV(TSM);

    setup_t0();
    setup_t1();

    /* Enable timers after configuration */
    GTCCR   &= ~ _BV(TSM);

    /* Enable Interrupts globally */
    SREG |= (1 << 7);
}

/******************************************************************************
 * setup_t0: Set up Timer 0 in a way such that it is running in phase-correct
 * Pulse Width Modulation (PWM) mode. OCR0A serves as TOP. OCR0B serves as the
 * comparison boundary. The timer is run off the internal oscillator.
 *****************************************************************************/
static void
setup_t0(void) {
    /* Clear IRQ Flags */
    TIFR    |= _BV(OCF0A) | _BV(OCF0B) | _BV(TOV0);

    /* Enable specific IRQs of Timer 0 */
    TIMSK   &= ~ (_BV(OCIE0A) | _BV(OCIE0B) | _BV(TOIE0));
    TIMSK   |= /* _BV(OCIE0A) | _BV(OCIE0B) | _BV(TOIE0) */ 0;

    OCR0A   = 255;  /* Set TOP */
    OCR0B   = g_status->m_curpwm;

    TCCR0A  = /* _BV(COM0A1) | ~_BV(COM0A0) | */ _BV(COM0B1) | /* ~_BV(COM0B0) | ~ _BV(WGM01) | */ _BV(WGM00);
    TCCR0B  = _BV(WGM02) | /* ~_BV(CS02) | ~_BV(CS01) | */ _BV(CS00);
}

ISR(TIM0_OVF_vect) {
    /* Disable timer 0 overflow interrupt while processing. */
    TIMSK   &= ~ _BV(TOIE0);
    TIFR    |= _BV(TOV0);

    OCR0B   = g_status->m_curpwm;
    TCNT0   = 0;

    /* Re-set timer to 0 and re-enable the interrupt. */
    TIMSK   |= _BV(TOIE0);
}

ISR(TIM0_COMPA_vect) {
    TIFR |= _BV(OCF0A);
}

ISR(TIM0_COMPB_vect) {
    TIFR |= _BV(OCF0B);
}


/******************************************************************************
 * Timer 1: Set up callback that is used to periodically update the PWM timer.
 * The timer pre-scaler is set to the maximum value, i.e. 16k. Hence, the timer
 * counts with a frequency of CLK/16k which is 512 Hz. The timer is set up to
 * count from 0 to 255 which generates an overflow interrupt twice per second.
 *****************************************************************************/
static void
setup_t1(void) {
    TCCR1   = /* _BV(CTC1) |  _BV(CS13) | _BV(CS12) | _BV(CS11) | _BV(CS10) */ 0x0c;
	
    TCNT1   = 0;
    OCR1A   = 4;
    OCR1B   = 128;
    OCR1C   = 255;

    TIFR    |= _BV(OCF1A) | _BV(OCF1B) | _BV(TOV1);
    TIMSK   |= /* _BV(OCIE1A) | _BV(OCIE1B) | */ _BV(TOIE1);
}

ISR(TIM1_OVF_vect) {
    /* Disable timer 1 overflow interrupt while processing. */
    TIMSK   &= ~ _BV(TOIE1);
    TIFR    |= _BV(TOV1);

    if (g_status->m_curdelay > 0)
        g_status->m_curdelay--;

    /* Re-set timer to 0 and re-enable the interrupt. */
    TCNT1   = 0;
    TIMSK   |= _BV(TOIE1);
}

ISR(TIM1_COMPA_vect) {
    TIFR |= _BV(OCF1A);
}

ISR(TIM1_COMPB_vect) {
    TIFR |= _BV(OCF1B);
}

/******************************************************************************
 * General Purpose I/O Pin Handling
 *****************************************************************************/
static void
setup_portb(void) {
	DDRB    = 0;

    DDRB    |= _BV(PINB1) | _BV(PINB3);
    PORTB   &= ~ _BV(PINB1);
	PORTB   |= _BV(PINB3);
}

/******************************************************************************
 *
 *****************************************************************************/
static void
btn_init(button_t *p_btn, uint8_t p_number, uint8_t p_threshold) {
	assert(p_btn != NULL);
    assert(p_number < 8);
    assert(p_threshold > 0);
	
    p_btn->m_status     = p_number & BTN_STATUS_NUMBER;
	p_btn->m_count      = 0;
	p_btn->m_threshold  = p_threshold;
}

/******************************************************************************
 *
 *****************************************************************************/
static void
btn_eval(button_t *p_btn) {
    int prev = 0, cur = 0, val = 0, pin;

	/*
	 * m_status is a bit-mask that encodes a bunch of stuff. Here, we're
	 * transferring the value of the current sample into the value of the prev.
	 * sample. Then, we're sampling the I/O Pin and storing the current value
	 * in the corresponding bit.
	 */
    p_btn->m_status &= ~ BTN_STATUS_PREVSAMPLE;
    if (p_btn->m_status & BTN_STATUS_CURSAMPLE) {
	    p_btn->m_status |= BTN_STATUS_PREVSAMPLE;
		prev = 1;
	}    
    p_btn->m_status &= ~ BTN_STATUS_CURSAMPLE;

    pin = p_btn->m_status & BTN_STATUS_NUMBER;
    if (PINB & (1 << pin)) {
	    p_btn->m_status |= BTN_STATUS_CURSAMPLE;
		cur = 1;
	}

    if (cur == prev) {
	    p_btn->m_count++;
	} else {
		p_btn->m_count = 0;
	}

    p_btn->m_status &= ~ (BTN_STATUS_POSEDGE | BTN_STATUS_NEGEDGE);
    if (p_btn->m_count == p_btn->m_threshold) {
		if (p_btn->m_status & BTN_STATUS_VALUE)
		    val = 1;

	    p_btn->m_status &= ~ BTN_STATUS_VALUE; 
		if (cur)
		    p_btn->m_status |= BTN_STATUS_VALUE;
			
		if (cur && !val)
		    p_btn->m_status |= BTN_STATUS_POSEDGE;
			
		if (!cur && val)
		    p_btn->m_status |= BTN_STATUS_NEGEDGE;
	}	
}

/******************************************************************************
 *
 *****************************************************************************/
static void
panic(void) {
    cli();

    /* Turn on Red Panic LED */
    PORTB   |= _BV(PINB3);
    DDRB    |= _BV(PINB3);

    /*
     * Disable Timers:
     * - Turn on Timer Sync. Mode
     * - Disconnect Timer from Output Pins
     * - Disconnect Clock Source from Timer
     */
    GTCCR   |= _BV(TSM);

    TCCR0A  &= ~(_BV(COM0A1) | _BV(COM0A0) | _BV(COM0B1) | _BV(COM0B0));
    TCCR0B  &= ~(_BV(CS02) | _BV(CS01) | _BV(CS00));

    TCCR1   &= ~(_BV(CS12) | _BV(CS12) | _BV(CS11) | _BV(CS10));

    /* Set Port B, Pin #0 low */
    PORTB   &= ~ _BV(PINB1);
    DDRB    &= ~ _BV(PINB1);

    while (1) {
    }

    /* NOTREACHED */
}

/******************************************************************************
 *
 *****************************************************************************/
static int
constrained_rand(int p_lo, int p_hi) {
	int val = (p_lo + (rand() % (p_hi - p_lo)));
	assert(val >= p_lo);
	assert(val <= p_hi);
	
	return (val);
}
