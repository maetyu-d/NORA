#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ctype.h>
#include <math.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SAMPLE_RATE 48000
#define CHANNELS 1
#define BUFFER_FRAMES 512
#define BUFFER_COUNT 3
#define INPUT_LINE_MAX 4096
#define SMOOTHING_COEFF 0.0008

typedef enum {
    TOK_EOF = 0,
    TOK_NUM,
    TOK_IDENT,
    TOK_LPAREN,
    TOK_RPAREN,
    TOK_COMMA,
    TOK_QUESTION,
    TOK_COLON,
    TOK_PLUS,
    TOK_MINUS,
    TOK_MUL,
    TOK_DIV,
    TOK_MOD,
    TOK_BNOT,
    TOK_LNOT,
    TOK_LT,
    TOK_GT,
    TOK_LE,
    TOK_GE,
    TOK_EQ,
    TOK_NE,
    TOK_AND,
    TOK_OR,
    TOK_BAND,
    TOK_BOR,
    TOK_BXOR,
    TOK_SHL,
    TOK_SHR,
    TOK_USHR
} TokenType;

typedef struct {
    TokenType type;
    double number;
    char ident[64];
} Token;

typedef struct {
    const char *src;
    size_t pos;
    Token tok;
    char err[256];
} Lexer;

typedef enum {
    EX_NUM,
    EX_VAR,
    EX_UNARY,
    EX_BINARY,
    EX_TERNARY,
    EX_FUNC
} ExprType;

typedef enum {
    VAR_T = 0,
    VAR_A,
    VAR_B,
    VAR_C,
    VAR_D,
    VAR_SH,
    VAR_MASK
} VarId;

typedef enum {
    OP_NEG,
    OP_BNOT,
    OP_LNOT,
    OP_ADD,
    OP_SUB,
    OP_MUL,
    OP_DIV,
    OP_MOD,
    OP_LT,
    OP_GT,
    OP_LE,
    OP_GE,
    OP_EQ,
    OP_NE,
    OP_LAND,
    OP_LOR,
    OP_BAND,
    OP_BOR,
    OP_BXOR,
    OP_SHL,
    OP_SHR,
    OP_USHR
} Op;

typedef struct Expr Expr;
struct Expr {
    ExprType type;
    union {
        double num;
        VarId var;
        struct {
            Op op;
            Expr *a;
        } unary;
        struct {
            Op op;
            Expr *a;
            Expr *b;
        } binary;
        struct {
            Expr *cond;
            Expr *yes;
            Expr *no;
        } ternary;
        struct {
            char name[16];
            Expr **args;
            int argc;
        } func;
    } as;
};

typedef struct {
    Lexer lx;
} Parser;

typedef struct {
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[BUFFER_COUNT];
    pthread_mutex_t expr_lock;
    Expr *expr;
    _Atomic double target_tempo;
    _Atomic double target_pitch;
    _Atomic double macro_a;
    _Atomic double macro_b;
    _Atomic double macro_c;
    _Atomic double macro_d;
    _Atomic double macro_shift;
    _Atomic double macro_mask;
    double smooth_tempo;
    double smooth_pitch;
    double timeline;
    int current_preset;
    _Atomic bool running;
} Synth;

static Synth g_synth;

typedef struct {
    const char *name;
    const char *js;
} Preset;

static const Preset kPresets[] = {
    {"Viznut Classic 1", "(t*(t>>a|t>>b))>>(t>>d)"},
    {"Viznut Classic 2", "t*(((t>>(a+d))|(t>>b))&((a*b)&(t>>c)))"},
    {"Viznut Classic 3", "(t*a&t>>b)|(t*c&t>>d)"},
    {"Crowd Pleaser 1", "(t>>a|t|t>>(t>>d))*b+((t>>c)&a)"},
    {"Crowd Pleaser 2", "t*(t>>a&t>>b&(a*c+d)&t>>c)"},
    {"Crowd Pleaser 3", "(t*(a+d)&t>>c|t*a&t>>b|t*c&t/(128*d))-1"},
    {"Bit Groove 1", "((t>>b)|(t>>c))*a+d*(t&t>>(a+d)|t>>c)"},
    {"Bit Groove 2", "t*(((t>>a)|(t>>(b+d)))&((a*5)&(t>>c)))"},
    {"Bit Groove 3", "t*(((t>>(a+2))&(t>>b))&((a*b*c)&(t>>d)))"},
    {"Drone Shift", "((t>>a)|(t>>b))*(t>>d)"},
    {"Chiptune Pulse", "(t>>c)|(t*a&(t>>d))"},
    {"Xor Bells", "((t>>d)^(t>>(d+1)))*(t&(a*b*c*d))"},
    {"Dual Arp", "((t*a)&(t>>(b+2)))|((t*c)&(t>>d))"},
    {"Modulo Melody", "((t>>(b+d))|(t%(a*c+d)))*(t%(a+b+c+d))"},
    {"Harsh Lead", "((t*(a+b+d))&(t>>b))^((t*c)&(t>>d))"},
    {"Sub Octaves", "((t>>a)*(t>>a)|(t>>c)|(t>>b))"},
    {"Detuned Saw", "((t*(a+b+d))&(t>>b))|((t*(c+d+a))&(t>>d))"},
    {"Clock Crunch", "((t>>b)&(t>>c))*t*a"},
    {"Stacked Bits", "((t*c)&(t>>d))|((t*a)&(t>>b))|((t*(a+b))&(t>>(b+d)))"},
    {"Riser Noise", "(t>>b)*(t>>a|t>>(c+d))"},
    {"Mask Jam", "(t*((t>>a)|(t>>(b+d))))&(a*b*c*d)"},
    {"Metal Ping", "(t*((a*b)&(t>>d)))^(t>>(b+d))"},
    {"Tri-Xor", "((t>>a)^(t>>b)^(t>>d))*t*c"},
    {"Macro Stack", "((t*a)&(t>>c))|((t*b)&(t>>d))"},
    {"Macro Shift Gate", "(t*(a&(t>>c)))|((t>>d)&b)"},
    {"Macro Cross", "((t>>a)|(t>>b))*(c+(t>>d))"},
    {"Macro Ternary", "(t>>a)?((t*b)&(t>>c)):((t*d)&(t>>b))"},
    {"Macro Xor Arp", "((t*a)^(t>>b))|((t*c)&(t>>d))"},
    {"Macro Bitsaw", "((t*(a+b))&(t>>(c+1)))|((t*(d+1))&(t>>a))"},
    {"Macro Finale", "((t*a&t>>b)|(t*c&t>>d))+(sin(t/(20+d))*32)"},
};

#define PRESET_COUNT ((int)(sizeof(kPresets) / sizeof(kPresets[0])))

static void expr_free(Expr *e) {
    if (!e) return;
    switch (e->type) {
        case EX_UNARY:
            expr_free(e->as.unary.a);
            break;
        case EX_BINARY:
            expr_free(e->as.binary.a);
            expr_free(e->as.binary.b);
            break;
        case EX_TERNARY:
            expr_free(e->as.ternary.cond);
            expr_free(e->as.ternary.yes);
            expr_free(e->as.ternary.no);
            break;
        case EX_FUNC:
            for (int i = 0; i < e->as.func.argc; ++i) expr_free(e->as.func.args[i]);
            free(e->as.func.args);
            break;
        default:
            break;
    }
    free(e);
}

static Expr *expr_new(ExprType t) {
    Expr *e = (Expr *)calloc(1, sizeof(Expr));
    if (!e) return NULL;
    e->type = t;
    return e;
}

static int32_t to_i32(double v) { return (int32_t)((int64_t)llround(floor(v))); }
static uint32_t to_u32(double v) { return (uint32_t)to_i32(v); }

static double fn_eval(const char *name, double *a, int n) {
    if (!strcmp(name, "sin") && n == 1) return sin(a[0]);
    if (!strcmp(name, "cos") && n == 1) return cos(a[0]);
    if (!strcmp(name, "tan") && n == 1) return tan(a[0]);
    if (!strcmp(name, "abs") && n == 1) return fabs(a[0]);
    if (!strcmp(name, "sqrt") && n == 1) return sqrt(fabs(a[0]));
    if (!strcmp(name, "floor") && n == 1) return floor(a[0]);
    if (!strcmp(name, "ceil") && n == 1) return ceil(a[0]);
    if (!strcmp(name, "pow") && n == 2) return pow(a[0], a[1]);
    if (!strcmp(name, "min") && n == 2) return fmin(a[0], a[1]);
    if (!strcmp(name, "max") && n == 2) return fmax(a[0], a[1]);
    if (!strcmp(name, "clamp") && n == 3) return fmax(a[1], fmin(a[2], a[0]));
    return 0.0;
}

typedef struct {
    double t;
    double a;
    double b;
    double c;
    double d;
    double sh;
    double mask;
} EvalContext;

static double eval_var(const EvalContext *ctx, VarId id) {
    switch (id) {
        case VAR_T:
            return ctx->t;
        case VAR_A:
            return ctx->a;
        case VAR_B:
            return ctx->b;
        case VAR_C:
            return ctx->c;
        case VAR_D:
            return ctx->d;
        case VAR_SH:
            return ctx->sh;
        case VAR_MASK:
            return ctx->mask;
    }
    return 0.0;
}

static double expr_eval(const Expr *e, const EvalContext *ctx) {
    switch (e->type) {
        case EX_NUM:
            return e->as.num;
        case EX_VAR:
            return eval_var(ctx, e->as.var);
        case EX_UNARY: {
            double a = expr_eval(e->as.unary.a, ctx);
            switch (e->as.unary.op) {
                case OP_NEG:
                    return -a;
                case OP_BNOT:
                    return (double)(~to_i32(a));
                case OP_LNOT:
                    return !a ? 1.0 : 0.0;
                default:
                    return 0.0;
            }
        }
        case EX_BINARY: {
            if (e->as.binary.op == OP_LAND) {
                double left = expr_eval(e->as.binary.a, ctx);
                return left ? (expr_eval(e->as.binary.b, ctx) ? 1.0 : 0.0) : 0.0;
            }
            if (e->as.binary.op == OP_LOR) {
                double left = expr_eval(e->as.binary.a, ctx);
                return left ? 1.0 : (expr_eval(e->as.binary.b, ctx) ? 1.0 : 0.0);
            }
            double a = expr_eval(e->as.binary.a, ctx);
            double b = expr_eval(e->as.binary.b, ctx);
            switch (e->as.binary.op) {
                case OP_ADD:
                    return a + b;
                case OP_SUB:
                    return a - b;
                case OP_MUL:
                    return a * b;
                case OP_DIV:
                    return fabs(b) < 1e-12 ? 0.0 : a / b;
                case OP_MOD: {
                    int32_t ib = to_i32(b);
                    return ib == 0 ? 0.0 : (double)(to_i32(a) % ib);
                }
                case OP_LT:
                    return a < b ? 1.0 : 0.0;
                case OP_GT:
                    return a > b ? 1.0 : 0.0;
                case OP_LE:
                    return a <= b ? 1.0 : 0.0;
                case OP_GE:
                    return a >= b ? 1.0 : 0.0;
                case OP_EQ:
                    return fabs(a - b) < 1e-12 ? 1.0 : 0.0;
                case OP_NE:
                    return fabs(a - b) >= 1e-12 ? 1.0 : 0.0;
                case OP_BAND:
                    return (double)(to_i32(a) & to_i32(b));
                case OP_BOR:
                    return (double)(to_i32(a) | to_i32(b));
                case OP_BXOR:
                    return (double)(to_i32(a) ^ to_i32(b));
                case OP_SHL:
                    return (double)(to_i32(a) << (to_i32(b) & 31));
                case OP_SHR:
                    return (double)(to_i32(a) >> (to_i32(b) & 31));
                case OP_USHR:
                    return (double)(to_u32(a) >> (to_i32(b) & 31));
                default:
                    return 0.0;
            }
        }
        case EX_TERNARY:
            return expr_eval(e->as.ternary.cond, ctx) ? expr_eval(e->as.ternary.yes, ctx)
                                                      : expr_eval(e->as.ternary.no, ctx);
        case EX_FUNC: {
            double vals[8] = {0};
            int argc = e->as.func.argc;
            if (argc > 8) argc = 8;
            for (int i = 0; i < argc; ++i) vals[i] = expr_eval(e->as.func.args[i], ctx);
            return fn_eval(e->as.func.name, vals, argc);
        }
    }
    return 0.0;
}

static void lexer_skip_ws(Lexer *lx) {
    while (isspace((unsigned char)lx->src[lx->pos])) lx->pos++;
}

static bool lexer_starts_with(Lexer *lx, const char *s) {
    size_t i = 0;
    while (s[i]) {
        if (lx->src[lx->pos + i] != s[i]) return false;
        i++;
    }
    return true;
}

static void lexer_next(Lexer *lx) {
    lexer_skip_ws(lx);
    lx->tok.type = TOK_EOF;
    lx->tok.number = 0;
    lx->tok.ident[0] = '\0';

    char c = lx->src[lx->pos];
    if (!c) {
        lx->tok.type = TOK_EOF;
        return;
    }

    if (isdigit((unsigned char)c)) {
        char *end = NULL;
        lx->tok.number = strtod(&lx->src[lx->pos], &end);
        lx->pos = (size_t)(end - lx->src);
        lx->tok.type = TOK_NUM;
        return;
    }

    if (isalpha((unsigned char)c) || c == '_') {
        size_t start = lx->pos;
        while (isalnum((unsigned char)lx->src[lx->pos]) || lx->src[lx->pos] == '_') lx->pos++;
        size_t len = lx->pos - start;
        if (len >= sizeof(lx->tok.ident)) len = sizeof(lx->tok.ident) - 1;
        memcpy(lx->tok.ident, lx->src + start, len);
        lx->tok.ident[len] = '\0';
        lx->tok.type = TOK_IDENT;
        return;
    }

    if (lexer_starts_with(lx, ">>>")) {
        lx->tok.type = TOK_USHR;
        lx->pos += 3;
        return;
    }
    if (lexer_starts_with(lx, "<<")) {
        lx->tok.type = TOK_SHL;
        lx->pos += 2;
        return;
    }
    if (lexer_starts_with(lx, ">>")) {
        lx->tok.type = TOK_SHR;
        lx->pos += 2;
        return;
    }
    if (lexer_starts_with(lx, "<=")) {
        lx->tok.type = TOK_LE;
        lx->pos += 2;
        return;
    }
    if (lexer_starts_with(lx, ">=")) {
        lx->tok.type = TOK_GE;
        lx->pos += 2;
        return;
    }
    if (lexer_starts_with(lx, "==")) {
        lx->tok.type = TOK_EQ;
        lx->pos += 2;
        return;
    }
    if (lexer_starts_with(lx, "!=")) {
        lx->tok.type = TOK_NE;
        lx->pos += 2;
        return;
    }
    if (lexer_starts_with(lx, "&&")) {
        lx->tok.type = TOK_AND;
        lx->pos += 2;
        return;
    }
    if (lexer_starts_with(lx, "||")) {
        lx->tok.type = TOK_OR;
        lx->pos += 2;
        return;
    }

    lx->pos++;
    switch (c) {
        case '(':
            lx->tok.type = TOK_LPAREN;
            break;
        case ')':
            lx->tok.type = TOK_RPAREN;
            break;
        case ',':
            lx->tok.type = TOK_COMMA;
            break;
        case '?':
            lx->tok.type = TOK_QUESTION;
            break;
        case ':':
            lx->tok.type = TOK_COLON;
            break;
        case '+':
            lx->tok.type = TOK_PLUS;
            break;
        case '-':
            lx->tok.type = TOK_MINUS;
            break;
        case '*':
            lx->tok.type = TOK_MUL;
            break;
        case '/':
            lx->tok.type = TOK_DIV;
            break;
        case '%':
            lx->tok.type = TOK_MOD;
            break;
        case '~':
            lx->tok.type = TOK_BNOT;
            break;
        case '!':
            lx->tok.type = TOK_LNOT;
            break;
        case '<':
            lx->tok.type = TOK_LT;
            break;
        case '>':
            lx->tok.type = TOK_GT;
            break;
        case '&':
            lx->tok.type = TOK_BAND;
            break;
        case '|':
            lx->tok.type = TOK_BOR;
            break;
        case '^':
            lx->tok.type = TOK_BXOR;
            break;
        default:
            snprintf(lx->err, sizeof(lx->err), "Unexpected character '%c'", c);
            lx->tok.type = TOK_EOF;
            break;
    }
}

static Expr *parse_expr(Parser *p);

static bool consume(Parser *p, TokenType t) {
    if (p->lx.tok.type == t) {
        lexer_next(&p->lx);
        return true;
    }
    return false;
}

static bool parse_var_id(const char *ident, VarId *out) {
    if (!strcmp(ident, "t")) {
        *out = VAR_T;
        return true;
    }
    if (!strcmp(ident, "a")) {
        *out = VAR_A;
        return true;
    }
    if (!strcmp(ident, "b")) {
        *out = VAR_B;
        return true;
    }
    if (!strcmp(ident, "c")) {
        *out = VAR_C;
        return true;
    }
    if (!strcmp(ident, "d")) {
        *out = VAR_D;
        return true;
    }
    if (!strcmp(ident, "sh")) {
        *out = VAR_SH;
        return true;
    }
    if (!strcmp(ident, "mask")) {
        *out = VAR_MASK;
        return true;
    }
    return false;
}

static Expr *parse_primary(Parser *p) {
    if (p->lx.tok.type == TOK_NUM) {
        Expr *e = expr_new(EX_NUM);
        if (!e) return NULL;
        e->as.num = p->lx.tok.number;
        lexer_next(&p->lx);
        return e;
    }

    if (p->lx.tok.type == TOK_IDENT) {
        char ident[64];
        strncpy(ident, p->lx.tok.ident, sizeof(ident) - 1);
        ident[sizeof(ident) - 1] = '\0';
        lexer_next(&p->lx);

        if (consume(p, TOK_LPAREN)) {
            Expr *e = expr_new(EX_FUNC);
            if (!e) return NULL;
            strncpy(e->as.func.name, ident, sizeof(e->as.func.name) - 1);
            e->as.func.name[sizeof(e->as.func.name) - 1] = '\0';
            e->as.func.argc = 0;
            e->as.func.args = NULL;

            if (!consume(p, TOK_RPAREN)) {
                while (1) {
                    Expr *arg = parse_expr(p);
                    if (!arg) {
                        expr_free(e);
                        return NULL;
                    }
                    Expr **next = realloc(e->as.func.args, sizeof(Expr *) * (size_t)(e->as.func.argc + 1));
                    if (!next) {
                        expr_free(arg);
                        expr_free(e);
                        return NULL;
                    }
                    e->as.func.args = next;
                    e->as.func.args[e->as.func.argc++] = arg;
                    if (consume(p, TOK_RPAREN)) break;
                    if (!consume(p, TOK_COMMA)) {
                        snprintf(p->lx.err, sizeof(p->lx.err), "Expected ',' or ')' in function args");
                        expr_free(e);
                        return NULL;
                    }
                }
            }
            return e;
        }

        VarId id;
        if (parse_var_id(ident, &id)) {
            Expr *e = expr_new(EX_VAR);
            if (!e) return NULL;
            e->as.var = id;
            return e;
        }

        snprintf(p->lx.err, sizeof(p->lx.err), "Unknown identifier '%s'", ident);
        return NULL;
    }

    if (consume(p, TOK_LPAREN)) {
        Expr *e = parse_expr(p);
        if (!e) return NULL;
        if (!consume(p, TOK_RPAREN)) {
            snprintf(p->lx.err, sizeof(p->lx.err), "Expected ')' ");
            expr_free(e);
            return NULL;
        }
        return e;
    }

    snprintf(p->lx.err, sizeof(p->lx.err), "Expected expression");
    return NULL;
}

static Expr *parse_unary(Parser *p) {
    if (consume(p, TOK_MINUS)) {
        Expr *a = parse_unary(p);
        if (!a) return NULL;
        Expr *e = expr_new(EX_UNARY);
        if (!e) {
            expr_free(a);
            return NULL;
        }
        e->as.unary.op = OP_NEG;
        e->as.unary.a = a;
        return e;
    }
    if (consume(p, TOK_BNOT)) {
        Expr *a = parse_unary(p);
        if (!a) return NULL;
        Expr *e = expr_new(EX_UNARY);
        if (!e) {
            expr_free(a);
            return NULL;
        }
        e->as.unary.op = OP_BNOT;
        e->as.unary.a = a;
        return e;
    }
    if (consume(p, TOK_LNOT)) {
        Expr *a = parse_unary(p);
        if (!a) return NULL;
        Expr *e = expr_new(EX_UNARY);
        if (!e) {
            expr_free(a);
            return NULL;
        }
        e->as.unary.op = OP_LNOT;
        e->as.unary.a = a;
        return e;
    }
    return parse_primary(p);
}

static Expr *parse_mul(Parser *p) {
    Expr *left = parse_unary(p);
    if (!left) return NULL;
    while (p->lx.tok.type == TOK_MUL || p->lx.tok.type == TOK_DIV || p->lx.tok.type == TOK_MOD) {
        TokenType tt = p->lx.tok.type;
        lexer_next(&p->lx);
        Expr *right = parse_unary(p);
        if (!right) {
            expr_free(left);
            return NULL;
        }
        Expr *e = expr_new(EX_BINARY);
        if (!e) {
            expr_free(left);
            expr_free(right);
            return NULL;
        }
        e->as.binary.op = tt == TOK_MUL ? OP_MUL : tt == TOK_DIV ? OP_DIV : OP_MOD;
        e->as.binary.a = left;
        e->as.binary.b = right;
        left = e;
    }
    return left;
}

static Expr *parse_add(Parser *p) {
    Expr *left = parse_mul(p);
    if (!left) return NULL;
    while (p->lx.tok.type == TOK_PLUS || p->lx.tok.type == TOK_MINUS) {
        TokenType tt = p->lx.tok.type;
        lexer_next(&p->lx);
        Expr *right = parse_mul(p);
        if (!right) {
            expr_free(left);
            return NULL;
        }
        Expr *e = expr_new(EX_BINARY);
        if (!e) {
            expr_free(left);
            expr_free(right);
            return NULL;
        }
        e->as.binary.op = tt == TOK_PLUS ? OP_ADD : OP_SUB;
        e->as.binary.a = left;
        e->as.binary.b = right;
        left = e;
    }
    return left;
}

static Expr *parse_shift(Parser *p) {
    Expr *left = parse_add(p);
    if (!left) return NULL;
    while (p->lx.tok.type == TOK_SHL || p->lx.tok.type == TOK_SHR || p->lx.tok.type == TOK_USHR) {
        TokenType tt = p->lx.tok.type;
        lexer_next(&p->lx);
        Expr *right = parse_add(p);
        if (!right) {
            expr_free(left);
            return NULL;
        }
        Expr *e = expr_new(EX_BINARY);
        if (!e) {
            expr_free(left);
            expr_free(right);
            return NULL;
        }
        e->as.binary.op = tt == TOK_SHL ? OP_SHL : tt == TOK_SHR ? OP_SHR : OP_USHR;
        e->as.binary.a = left;
        e->as.binary.b = right;
        left = e;
    }
    return left;
}

static Expr *parse_rel(Parser *p) {
    Expr *left = parse_shift(p);
    if (!left) return NULL;
    while (p->lx.tok.type == TOK_LT || p->lx.tok.type == TOK_GT || p->lx.tok.type == TOK_LE ||
           p->lx.tok.type == TOK_GE) {
        TokenType tt = p->lx.tok.type;
        lexer_next(&p->lx);
        Expr *right = parse_shift(p);
        if (!right) {
            expr_free(left);
            return NULL;
        }
        Expr *e = expr_new(EX_BINARY);
        if (!e) {
            expr_free(left);
            expr_free(right);
            return NULL;
        }
        e->as.binary.op = tt == TOK_LT   ? OP_LT
                          : tt == TOK_GT ? OP_GT
                          : tt == TOK_LE ? OP_LE
                                          : OP_GE;
        e->as.binary.a = left;
        e->as.binary.b = right;
        left = e;
    }
    return left;
}

static Expr *parse_eq(Parser *p) {
    Expr *left = parse_rel(p);
    if (!left) return NULL;
    while (p->lx.tok.type == TOK_EQ || p->lx.tok.type == TOK_NE) {
        TokenType tt = p->lx.tok.type;
        lexer_next(&p->lx);
        Expr *right = parse_rel(p);
        if (!right) {
            expr_free(left);
            return NULL;
        }
        Expr *e = expr_new(EX_BINARY);
        if (!e) {
            expr_free(left);
            expr_free(right);
            return NULL;
        }
        e->as.binary.op = tt == TOK_EQ ? OP_EQ : OP_NE;
        e->as.binary.a = left;
        e->as.binary.b = right;
        left = e;
    }
    return left;
}

static Expr *parse_band(Parser *p) {
    Expr *left = parse_eq(p);
    if (!left) return NULL;
    while (p->lx.tok.type == TOK_BAND) {
        lexer_next(&p->lx);
        Expr *right = parse_eq(p);
        if (!right) {
            expr_free(left);
            return NULL;
        }
        Expr *e = expr_new(EX_BINARY);
        if (!e) {
            expr_free(left);
            expr_free(right);
            return NULL;
        }
        e->as.binary.op = OP_BAND;
        e->as.binary.a = left;
        e->as.binary.b = right;
        left = e;
    }
    return left;
}

static Expr *parse_bxor(Parser *p) {
    Expr *left = parse_band(p);
    if (!left) return NULL;
    while (p->lx.tok.type == TOK_BXOR) {
        lexer_next(&p->lx);
        Expr *right = parse_band(p);
        if (!right) {
            expr_free(left);
            return NULL;
        }
        Expr *e = expr_new(EX_BINARY);
        if (!e) {
            expr_free(left);
            expr_free(right);
            return NULL;
        }
        e->as.binary.op = OP_BXOR;
        e->as.binary.a = left;
        e->as.binary.b = right;
        left = e;
    }
    return left;
}

static Expr *parse_bor(Parser *p) {
    Expr *left = parse_bxor(p);
    if (!left) return NULL;
    while (p->lx.tok.type == TOK_BOR) {
        lexer_next(&p->lx);
        Expr *right = parse_bxor(p);
        if (!right) {
            expr_free(left);
            return NULL;
        }
        Expr *e = expr_new(EX_BINARY);
        if (!e) {
            expr_free(left);
            expr_free(right);
            return NULL;
        }
        e->as.binary.op = OP_BOR;
        e->as.binary.a = left;
        e->as.binary.b = right;
        left = e;
    }
    return left;
}

static Expr *parse_land(Parser *p) {
    Expr *left = parse_bor(p);
    if (!left) return NULL;
    while (p->lx.tok.type == TOK_AND) {
        lexer_next(&p->lx);
        Expr *right = parse_bor(p);
        if (!right) {
            expr_free(left);
            return NULL;
        }
        Expr *e = expr_new(EX_BINARY);
        if (!e) {
            expr_free(left);
            expr_free(right);
            return NULL;
        }
        e->as.binary.op = OP_LAND;
        e->as.binary.a = left;
        e->as.binary.b = right;
        left = e;
    }
    return left;
}

static Expr *parse_lor(Parser *p) {
    Expr *left = parse_land(p);
    if (!left) return NULL;
    while (p->lx.tok.type == TOK_OR) {
        lexer_next(&p->lx);
        Expr *right = parse_land(p);
        if (!right) {
            expr_free(left);
            return NULL;
        }
        Expr *e = expr_new(EX_BINARY);
        if (!e) {
            expr_free(left);
            expr_free(right);
            return NULL;
        }
        e->as.binary.op = OP_LOR;
        e->as.binary.a = left;
        e->as.binary.b = right;
        left = e;
    }
    return left;
}

static Expr *parse_cond(Parser *p) {
    Expr *cond = parse_lor(p);
    if (!cond) return NULL;
    if (!consume(p, TOK_QUESTION)) return cond;

    Expr *yes = parse_expr(p);
    if (!yes) {
        expr_free(cond);
        return NULL;
    }
    if (!consume(p, TOK_COLON)) {
        snprintf(p->lx.err, sizeof(p->lx.err), "Expected ':' in ternary operator");
        expr_free(cond);
        expr_free(yes);
        return NULL;
    }
    Expr *no = parse_cond(p);
    if (!no) {
        expr_free(cond);
        expr_free(yes);
        return NULL;
    }
    Expr *e = expr_new(EX_TERNARY);
    if (!e) {
        expr_free(cond);
        expr_free(yes);
        expr_free(no);
        return NULL;
    }
    e->as.ternary.cond = cond;
    e->as.ternary.yes = yes;
    e->as.ternary.no = no;
    return e;
}

static Expr *parse_expr(Parser *p) { return parse_cond(p); }

static char *str_trim_copy(const char *s) {
    while (*s && isspace((unsigned char)*s)) s++;
    size_t len = strlen(s);
    while (len > 0 && isspace((unsigned char)s[len - 1])) len--;
    char *out = (char *)malloc(len + 1);
    if (!out) return NULL;
    memcpy(out, s, len);
    out[len] = '\0';
    return out;
}

static char *extract_js_expr(const char *js) {
    const char *r = strstr(js, "return");
    if (r) {
        r += 6;
        while (*r && isspace((unsigned char)*r)) r++;
        const char *end = strchr(r, ';');
        if (!end) end = js + strlen(js);
        size_t len = (size_t)(end - r);
        char *tmp = (char *)malloc(len + 1);
        if (!tmp) return NULL;
        memcpy(tmp, r, len);
        tmp[len] = '\0';
        char *trimmed = str_trim_copy(tmp);
        free(tmp);
        return trimmed;
    }
    return str_trim_copy(js);
}

static char *transpile_js_to_c(const char *js) {
    char *expr = extract_js_expr(js);
    if (!expr) return NULL;

    size_t in_len = strlen(expr);
    char *out = (char *)malloc(in_len * 2 + 1);
    if (!out) {
        free(expr);
        return NULL;
    }

    size_t i = 0, o = 0;
    while (i < in_len) {
        if (i + 5 <= in_len && !strncmp(expr + i, "Math.", 5)) {
            i += 5;
            continue;
        }
        if (expr[i] == '|' && i + 1 < in_len && expr[i + 1] == '|') {
            out[o++] = '|';
            out[o++] = '|';
            i += 2;
            continue;
        }
        if (expr[i] == '&' && i + 1 < in_len && expr[i + 1] == '&') {
            out[o++] = '&';
            out[o++] = '&';
            i += 2;
            continue;
        }
        out[o++] = expr[i++];
    }
    out[o] = '\0';
    free(expr);
    return out;
}

static Expr *compile_expr(const char *src, char *err, size_t err_sz) {
    Parser p;
    memset(&p, 0, sizeof(p));
    p.lx.src = src;
    lexer_next(&p.lx);

    Expr *root = parse_expr(&p);
    if (!root) {
        snprintf(err, err_sz, "%s", p.lx.err[0] ? p.lx.err : "Parse error");
        return NULL;
    }
    if (p.lx.tok.type != TOK_EOF) {
        snprintf(err, err_sz, "Unexpected trailing tokens");
        expr_free(root);
        return NULL;
    }
    err[0] = '\0';
    return root;
}

static inline float bytebeat_to_float(double v) {
    uint8_t b = (uint8_t)(to_i32(v) & 0xFF);
    return ((float)b - 128.0f) / 128.0f;
}

static void fill_buffer(Synth *s, AudioQueueBufferRef buf) {
    int16_t *pcm = (int16_t *)buf->mAudioData;
    const int n = BUFFER_FRAMES;

    pthread_mutex_lock(&s->expr_lock);
    Expr *expr = s->expr;
    for (int i = 0; i < n; ++i) {
        double targetTempo = atomic_load_explicit(&s->target_tempo, memory_order_relaxed);
        double targetPitch = atomic_load_explicit(&s->target_pitch, memory_order_relaxed);
        double macroA = atomic_load_explicit(&s->macro_a, memory_order_relaxed);
        double macroB = atomic_load_explicit(&s->macro_b, memory_order_relaxed);
        double macroC = atomic_load_explicit(&s->macro_c, memory_order_relaxed);
        double macroD = atomic_load_explicit(&s->macro_d, memory_order_relaxed);
        double macroShift = atomic_load_explicit(&s->macro_shift, memory_order_relaxed);
        double macroMask = atomic_load_explicit(&s->macro_mask, memory_order_relaxed);
        s->smooth_tempo += (targetTempo - s->smooth_tempo) * SMOOTHING_COEFF;
        s->smooth_pitch += (targetPitch - s->smooth_pitch) * SMOOTHING_COEFF;

        if (s->smooth_tempo < 0.05) s->smooth_tempo = 0.05;
        if (s->smooth_pitch < 0.125) s->smooth_pitch = 0.125;

        s->timeline += s->smooth_tempo;
        EvalContext ctx;
        memset(&ctx, 0, sizeof(ctx));
        ctx.t = floor(s->timeline * s->smooth_pitch);
        ctx.a = macroA;
        ctx.b = macroB;
        ctx.c = macroC;
        ctx.d = macroD;
        ctx.sh = floor(macroShift + 0.5);
        ctx.mask = floor(macroMask + 0.5);

        double y = expr ? expr_eval(expr, &ctx) : 0.0;
        float sample = bytebeat_to_float(y) * 0.6f;
        int16_t s16 = (int16_t)fmaxf(-32768.0f, fminf(32767.0f, sample * 32767.0f));
        pcm[i] = s16;
    }
    pthread_mutex_unlock(&s->expr_lock);

    buf->mAudioDataByteSize = (UInt32)(n * (int)sizeof(int16_t));
}

static void audio_cb(void *user, AudioQueueRef q, AudioQueueBufferRef buf) {
    (void)q;
    Synth *s = (Synth *)user;
    if (!atomic_load_explicit(&s->running, memory_order_relaxed)) return;
    fill_buffer(s, buf);
    AudioQueueEnqueueBuffer(s->queue, buf, 0, NULL);
}

static bool audio_start(Synth *s) {
    AudioStreamBasicDescription fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.mSampleRate = SAMPLE_RATE;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    fmt.mBitsPerChannel = 16;
    fmt.mChannelsPerFrame = CHANNELS;
    fmt.mBytesPerFrame = CHANNELS * 2;
    fmt.mFramesPerPacket = 1;
    fmt.mBytesPerPacket = fmt.mBytesPerFrame;

    OSStatus st = AudioQueueNewOutput(&fmt, audio_cb, s, NULL, NULL, 0, &s->queue);
    if (st != noErr) {
        fprintf(stderr, "AudioQueueNewOutput failed: %d\n", (int)st);
        return false;
    }

    for (int i = 0; i < BUFFER_COUNT; ++i) {
        st = AudioQueueAllocateBuffer(s->queue, BUFFER_FRAMES * sizeof(int16_t), &s->buffers[i]);
        if (st != noErr) {
            fprintf(stderr, "AudioQueueAllocateBuffer failed: %d\n", (int)st);
            return false;
        }
        fill_buffer(s, s->buffers[i]);
        AudioQueueEnqueueBuffer(s->queue, s->buffers[i], 0, NULL);
    }

    st = AudioQueueStart(s->queue, NULL);
    if (st != noErr) {
        fprintf(stderr, "AudioQueueStart failed: %d\n", (int)st);
        return false;
    }
    return true;
}

static void audio_stop(Synth *s) {
    if (s->queue) {
        AudioQueueStop(s->queue, true);
        AudioQueueDispose(s->queue, true);
        s->queue = NULL;
    }
}

static void print_help(void) {
    printf("Commands:\n");
    printf("  eq <js_expr_or_js_return_program>  Set bytebeat equation\n");
    printf("  a <value>                          Set macro a (float)\n");
    printf("  b <value>                          Set macro b (float)\n");
    printf("  c <value>                          Set macro c (float)\n");
    printf("  d <value>                          Set macro d (float)\n");
    printf("  sh <value>                         Set bit-shift macro (integer-ish)\n");
    printf("  mask <value>                       Set bitmask macro (integer-ish)\n");
    printf("  pl                                 List all built-in presets\n");
    printf("  ps <index>                         Switch to preset index (1..%d)\n", PRESET_COUNT);
    printf("  pn                                 Next preset\n");
    printf("  pp                                 Previous preset\n");
    printf("  p <semitones>                      Set pitch shift in semitones (e.g. -12, +7)\n");
    printf("  tm <multiplier>                    Set tempo multiplier (0.05..8.0)\n");
    printf("  s                                  Show current controls\n");
    printf("  h                                  Help\n");
    printf("  q                                  Quit\n");
}

static bool set_expr(Synth *s, const char *js) {
    char *c_expr = transpile_js_to_c(js);
    if (!c_expr) {
        fprintf(stderr, "Failed to transpile equation\n");
        return false;
    }

    char err[256];
    Expr *root = compile_expr(c_expr, err, sizeof(err));
    if (!root) {
        fprintf(stderr, "Compile error: %s\n", err);
        free(c_expr);
        return false;
    }

    pthread_mutex_lock(&s->expr_lock);
    Expr *old = s->expr;
    s->expr = root;
    pthread_mutex_unlock(&s->expr_lock);
    expr_free(old);

    printf("JS -> C: %s\n", c_expr);
    free(c_expr);
    return true;
}

static void print_presets(const Synth *s) {
    puts("Built-in bytebeat presets:");
    for (int i = 0; i < PRESET_COUNT; ++i) {
        const char *marker = (i == s->current_preset) ? "*" : " ";
        printf(" %s %2d. %s\n", marker, i + 1, kPresets[i].name);
    }
}

static void set_preset(Synth *s, int idx) {
    if (idx < 0 || idx >= PRESET_COUNT) {
        fprintf(stderr, "Preset index out of range (1..%d)\n", PRESET_COUNT);
        return;
    }
    if (set_expr(s, kPresets[idx].js)) {
        s->current_preset = idx;
        printf("Preset %d selected: %s\n", idx + 1, kPresets[idx].name);
    }
}

static void on_sigint(int sig) {
    (void)sig;
    atomic_store_explicit(&g_synth.running, false, memory_order_relaxed);
}

int main(void) {
    memset(&g_synth, 0, sizeof(g_synth));
    pthread_mutex_init(&g_synth.expr_lock, NULL);
    atomic_store_explicit(&g_synth.target_tempo, 1.0, memory_order_relaxed);
    atomic_store_explicit(&g_synth.target_pitch, 1.0, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_a, 5.0, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_b, 3.0, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_c, 7.0, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_d, 10.0, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_shift, 8.0, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_mask, 127.0, memory_order_relaxed);
    g_synth.smooth_tempo = 1.0;
    g_synth.smooth_pitch = 1.0;
    atomic_store_explicit(&g_synth.running, true, memory_order_relaxed);

    signal(SIGINT, on_sigint);

    g_synth.current_preset = 0;
    set_preset(&g_synth, g_synth.current_preset);

    if (!audio_start(&g_synth)) {
        expr_free(g_synth.expr);
        pthread_mutex_destroy(&g_synth.expr_lock);
        return 1;
    }

    puts("Realtime Bytebeat Synth (JS -> C transpile)");
    print_help();

    char line[INPUT_LINE_MAX];
    while (atomic_load_explicit(&g_synth.running, memory_order_relaxed)) {
        printf("> ");
        fflush(stdout);
        if (!fgets(line, sizeof(line), stdin)) break;

        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\n') line[len - 1] = '\0';

        if (!strncmp(line, "eq ", 3)) {
            if (set_expr(&g_synth, line + 3)) {
                g_synth.current_preset = -1;
            }
        } else if (!strncmp(line, "a ", 2)) {
            atomic_store_explicit(&g_synth.macro_a, strtod(line + 2, NULL), memory_order_relaxed);
        } else if (!strncmp(line, "b ", 2)) {
            atomic_store_explicit(&g_synth.macro_b, strtod(line + 2, NULL), memory_order_relaxed);
        } else if (!strncmp(line, "c ", 2)) {
            atomic_store_explicit(&g_synth.macro_c, strtod(line + 2, NULL), memory_order_relaxed);
        } else if (!strncmp(line, "d ", 2)) {
            atomic_store_explicit(&g_synth.macro_d, strtod(line + 2, NULL), memory_order_relaxed);
        } else if (!strncmp(line, "sh ", 3)) {
            atomic_store_explicit(&g_synth.macro_shift, strtod(line + 3, NULL), memory_order_relaxed);
        } else if (!strncmp(line, "mask ", 5)) {
            atomic_store_explicit(&g_synth.macro_mask, strtod(line + 5, NULL), memory_order_relaxed);
        } else if (!strcmp(line, "pl")) {
            print_presets(&g_synth);
        } else if (!strncmp(line, "ps ", 3)) {
            int idx = (int)strtol(line + 3, NULL, 10);
            set_preset(&g_synth, idx - 1);
        } else if (!strcmp(line, "pn")) {
            int idx = g_synth.current_preset;
            if (idx < 0) idx = 0;
            idx = (idx + 1) % PRESET_COUNT;
            set_preset(&g_synth, idx);
        } else if (!strcmp(line, "pp")) {
            int idx = g_synth.current_preset;
            if (idx < 0) idx = 0;
            idx = (idx - 1 + PRESET_COUNT) % PRESET_COUNT;
            set_preset(&g_synth, idx);
        } else if (!strncmp(line, "p ", 2)) {
            double semitones = strtod(line + 2, NULL);
            double ratio = pow(2.0, semitones / 12.0);
            atomic_store_explicit(&g_synth.target_pitch, ratio, memory_order_relaxed);
            printf("Pitch target set: %.2f semitones (x%.4f)\n", semitones, ratio);
        } else if (!strncmp(line, "tm ", 3)) {
            double tm = strtod(line + 3, NULL);
            if (tm < 0.05) tm = 0.05;
            if (tm > 8.0) tm = 8.0;
            atomic_store_explicit(&g_synth.target_tempo, tm, memory_order_relaxed);
            printf("Tempo target set: x%.3f\n", tm);
        } else if (!strcmp(line, "s")) {
            double tp = atomic_load_explicit(&g_synth.target_tempo, memory_order_relaxed);
            double pp = atomic_load_explicit(&g_synth.target_pitch, memory_order_relaxed);
            double a = atomic_load_explicit(&g_synth.macro_a, memory_order_relaxed);
            double b = atomic_load_explicit(&g_synth.macro_b, memory_order_relaxed);
            double c = atomic_load_explicit(&g_synth.macro_c, memory_order_relaxed);
            double d = atomic_load_explicit(&g_synth.macro_d, memory_order_relaxed);
            double sh = atomic_load_explicit(&g_synth.macro_shift, memory_order_relaxed);
            double mask = atomic_load_explicit(&g_synth.macro_mask, memory_order_relaxed);
            if (g_synth.current_preset >= 0) {
                printf("Preset %d: %s\n", g_synth.current_preset + 1, kPresets[g_synth.current_preset].name);
            } else {
                puts("Preset: custom equation");
            }
            printf("Target tempo x%.3f | target pitch ratio x%.4f\n", tp, pp);
            printf("Macros: a=%.3f b=%.3f c=%.3f d=%.3f sh=%d mask=%d\n", a, b, c, d, (int)llround(sh),
                   (int)llround(mask));
        } else if (!strcmp(line, "h")) {
            print_help();
        } else if (!strcmp(line, "q")) {
            break;
        } else if (line[0]) {
            puts("Unknown command. Type 'h' for help.");
        }
    }

    atomic_store_explicit(&g_synth.running, false, memory_order_relaxed);
    audio_stop(&g_synth);

    pthread_mutex_lock(&g_synth.expr_lock);
    Expr *final_expr = g_synth.expr;
    g_synth.expr = NULL;
    pthread_mutex_unlock(&g_synth.expr_lock);
    expr_free(final_expr);

    pthread_mutex_destroy(&g_synth.expr_lock);
    return 0;
}
