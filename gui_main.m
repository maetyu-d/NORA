#define main bytebeat_cli_main
#include "main.c"
#undef main

#import <Cocoa/Cocoa.h>
#import <objc/message.h>

@interface MacroVizView : NSView
@property double a;
@property double b;
@property double c;
@property double d;
@property double sh;
@property double mask;
@end

@implementation MacroVizView

static double clamp01(double v) {
    if (v < 0.0) return 0.0;
    if (v > 1.0) return 1.0;
    return v;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedWhite:0.1 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    NSDictionary *labelAttrs = @{
        NSFontAttributeName : [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:0.9 alpha:1.0]
    };

    const char *names[6] = {"a", "b", "c", "d", "sh", "mask"};
    double values[6] = {self.a, self.b, self.c, self.d, self.sh, self.mask};
    double norms[6] = {
        clamp01((self.a + 64.0) / 128.0), clamp01((self.b + 64.0) / 128.0), clamp01((self.c + 64.0) / 128.0),
        clamp01((self.d + 64.0) / 128.0), clamp01(self.sh / 16.0),         clamp01(self.mask / 255.0)};

    NSColor *colors[6] = {[NSColor colorWithCalibratedRed:0.97 green:0.42 blue:0.32 alpha:1.0],
                          [NSColor colorWithCalibratedRed:0.94 green:0.62 blue:0.20 alpha:1.0],
                          [NSColor colorWithCalibratedRed:0.95 green:0.84 blue:0.18 alpha:1.0],
                          [NSColor colorWithCalibratedRed:0.24 green:0.76 blue:0.37 alpha:1.0],
                          [NSColor colorWithCalibratedRed:0.16 green:0.69 blue:0.80 alpha:1.0],
                          [NSColor colorWithCalibratedRed:0.56 green:0.50 blue:0.93 alpha:1.0]};

    CGFloat pad = 12.0;
    CGFloat graphBottom = 20.0;
    CGFloat graphHeight = self.bounds.size.height - graphBottom - 8.0;
    CGFloat segment = (self.bounds.size.width - pad * 2.0) / 6.0;
    CGFloat barWidth = segment * 0.52;

    [[NSColor colorWithCalibratedWhite:0.22 alpha:1.0] setStroke];
    NSBezierPath *mid = [NSBezierPath bezierPath];
    [mid setLineWidth:1.0];
    [mid moveToPoint:NSMakePoint(pad, graphBottom + graphHeight * 0.5)];
    [mid lineToPoint:NSMakePoint(self.bounds.size.width - pad, graphBottom + graphHeight * 0.5)];
    [mid stroke];

    for (int i = 0; i < 6; ++i) {
        CGFloat x = pad + i * segment + (segment - barWidth) * 0.5;
        CGFloat h = (CGFloat)(norms[i] * graphHeight);
        NSRect bgRect = NSMakeRect(x, graphBottom, barWidth, graphHeight);
        [[NSColor colorWithCalibratedWhite:0.17 alpha:1.0] setFill];
        NSRectFill(bgRect);

        NSRect barRect = NSMakeRect(x, graphBottom, barWidth, h);
        [colors[i] setFill];
        NSRectFill(barRect);

        NSString *tag = [NSString stringWithFormat:@"%s %.0f", names[i], values[i]];
        [tag drawAtPoint:NSMakePoint(x - 8.0, 3.0) withAttributes:labelAttrs];
    }
}

@end

@interface WavePreviewView : NSView
- (void)updateWithSamples:(const float *)samples count:(int)count;
@end

@implementation WavePreviewView {
    float _samples[256];
    int _count;
}

- (void)updateWithSamples:(const float *)samples count:(int)count {
    if (!samples || count <= 0) {
        _count = 0;
        [self setNeedsDisplay:YES];
        return;
    }
    if (count > 256) count = 256;
    memcpy(_samples, samples, (size_t)count * sizeof(float));
    _count = count;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedWhite:0.08 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    CGFloat midY = self.bounds.size.height * 0.5;
    [[NSColor colorWithCalibratedWhite:0.25 alpha:1.0] setStroke];
    NSBezierPath *mid = [NSBezierPath bezierPath];
    [mid moveToPoint:NSMakePoint(0, midY)];
    [mid lineToPoint:NSMakePoint(self.bounds.size.width, midY)];
    [mid setLineWidth:1.0];
    [mid stroke];

    if (_count <= 1) return;

    [[NSColor colorWithCalibratedRed:0.22 green:0.93 blue:0.78 alpha:1.0] setStroke];
    NSBezierPath *wave = [NSBezierPath bezierPath];
    [wave setLineWidth:1.25];
    for (int i = 0; i < _count; ++i) {
        CGFloat x = ((CGFloat)i / (CGFloat)(_count - 1)) * self.bounds.size.width;
        CGFloat y = midY + _samples[i] * (self.bounds.size.height * 0.42);
        if (i == 0) {
            [wave moveToPoint:NSMakePoint(x, y)];
        } else {
            [wave lineToPoint:NSMakePoint(x, y)];
        }
    }
    [wave stroke];
}

@end

@interface EquationVisualView : NSView
@property(nonatomic, copy) NSString *equation;
@end

@implementation EquationVisualView

static BOOL is_ident_char(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

static NSColor *macro_color(char macro, CGFloat alpha) {
    switch (macro) {
        case 'a':
            return [NSColor colorWithCalibratedRed:0.96 green:0.45 blue:0.33 alpha:alpha];
        case 'b':
            return [NSColor colorWithCalibratedRed:0.95 green:0.74 blue:0.24 alpha:alpha];
        case 'c':
            return [NSColor colorWithCalibratedRed:0.27 green:0.83 blue:0.40 alpha:alpha];
        case 'd':
            return [NSColor colorWithCalibratedRed:0.30 green:0.66 blue:0.95 alpha:alpha];
        default:
            return [NSColor colorWithCalibratedWhite:0.9 alpha:alpha];
    }
}

- (void)setEquation:(NSString *)equation {
    _equation = [equation copy];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedWhite:0.09 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    NSDictionary *eqAttrs = @{
        NSFontAttributeName : [NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:0.95 alpha:1.0]
    };

    NSString *eq = self.equation ? self.equation : @"";
    if (eq.length == 0) return;

    NSRect textRect = NSInsetRect(self.bounds, 12.0, 12.0);
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentCenter;
    para.lineBreakMode = NSLineBreakByCharWrapping;

    NSMutableDictionary *baseAttrs = [eqAttrs mutableCopy];
    baseAttrs[NSParagraphStyleAttributeName] = para;

    NSMutableAttributedString *attrEq = [[NSMutableAttributedString alloc] initWithString:eq attributes:baseAttrs];
    for (NSUInteger i = 0; i < eq.length; ++i) {
        unichar ch = [eq characterAtIndex:i];
        char mappedMacro = 0;
        if ((char)tolower(ch) == 'a') mappedMacro = 'a';
        if ((char)tolower(ch) == 'b') mappedMacro = 'b';
        if ((char)tolower(ch) == 'c') mappedMacro = 'c';
        if ((char)tolower(ch) == 'd') mappedMacro = 'd';
        BOOL isMacroToken = NO;
        if (mappedMacro) {
            unichar prev = (i > 0) ? [eq characterAtIndex:i - 1] : ' ';
            unichar next = (i + 1 < eq.length) ? [eq characterAtIndex:i + 1] : ' ';
            isMacroToken = (!is_ident_char(prev) && !is_ident_char(next));
        }
        if (isMacroToken) {
            [attrEq addAttribute:NSForegroundColorAttributeName
                           value:macro_color(mappedMacro, 1.0)
                           range:NSMakeRange(i, 1)];
        }
    }

    NSStringDrawingOptions opts = NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading;
    NSRect needed = [attrEq boundingRectWithSize:NSMakeSize(textRect.size.width, CGFLOAT_MAX) options:opts];
    CGFloat h = ceil(needed.size.height);
    if (h < 1.0) h = 1.0;
    CGFloat y = textRect.origin.y + floor((textRect.size.height - h) * 0.5);
    if (y < textRect.origin.y) y = textRect.origin.y;
    NSRect drawRect = NSMakeRect(textRect.origin.x, y, textRect.size.width, h);
    [attrEq drawWithRect:drawRect options:opts context:nil];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(strong) NSWindow *window;
@property(strong) NSTextField *equationField;
@property(strong) NSPopUpButton *presetPopup;
@property(strong) NSSlider *pitchSlider;
@property(strong) NSSlider *tempoSlider;
@property(strong) NSTextField *pitchValue;
@property(strong) NSTextField *tempoValue;
@property(strong) NSTextField *statusLabel;
@property(strong) NSSlider *aSlider;
@property(strong) NSSlider *bSlider;
@property(strong) NSSlider *cSlider;
@property(strong) NSSlider *dSlider;
@property(strong) NSSlider *shiftSlider;
@property(strong) NSSlider *maskSlider;
@property(strong) NSTextField *aValue;
@property(strong) NSTextField *bValue;
@property(strong) NSTextField *cValue;
@property(strong) NSTextField *dValue;
@property(strong) NSTextField *shiftValue;
@property(strong) NSTextField *maskValue;
@property(strong) MacroVizView *macroViz;
@property(strong) WavePreviewView *waveViz;
@property(strong) NSTimer *vizTimer;
@property(strong) EquationVisualView *visualView;
@end

@implementation AppDelegate

static void set_slider_track_color(NSSlider *slider, NSColor *color) {
    SEL sel = NSSelectorFromString(@"setTrackFillColor:");
    if ([slider respondsToSelector:sel]) {
        ((void (*)(id, SEL, NSColor *))objc_msgSend)(slider, sel, color);
    }
    slider.wantsLayer = YES;
    slider.layer.cornerRadius = 4.0;
    slider.layer.borderWidth = 1.0;
    slider.layer.borderColor = [color colorWithAlphaComponent:0.55].CGColor;
}

static bool write_wav16_mono(const char *path, const int16_t *samples, uint32_t frameCount, uint32_t sampleRate) {
    FILE *f = fopen(path, "wb");
    if (!f) return false;

    const uint16_t audioFormat = 1;  // PCM
    const uint16_t channels = 1;
    const uint16_t bitsPerSample = 16;
    const uint32_t byteRate = sampleRate * channels * (bitsPerSample / 8);
    const uint16_t blockAlign = channels * (bitsPerSample / 8);
    const uint32_t dataSize = frameCount * blockAlign;
    const uint32_t chunkSize = 36 + dataSize;

    fwrite("RIFF", 1, 4, f);
    fwrite(&chunkSize, sizeof(chunkSize), 1, f);
    fwrite("WAVE", 1, 4, f);

    fwrite("fmt ", 1, 4, f);
    uint32_t fmtSize = 16;
    fwrite(&fmtSize, sizeof(fmtSize), 1, f);
    fwrite(&audioFormat, sizeof(audioFormat), 1, f);
    fwrite(&channels, sizeof(channels), 1, f);
    fwrite(&sampleRate, sizeof(sampleRate), 1, f);
    fwrite(&byteRate, sizeof(byteRate), 1, f);
    fwrite(&blockAlign, sizeof(blockAlign), 1, f);
    fwrite(&bitsPerSample, sizeof(bitsPerSample), 1, f);

    fwrite("data", 1, 4, f);
    fwrite(&dataSize, sizeof(dataSize), 1, f);
    fwrite(samples, sizeof(int16_t), frameCount, f);

    fclose(f);
    return true;
}

- (NSTextField *)label:(NSRect)frame text:(NSString *)text {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.textColor = [NSColor labelColor];
    return label;
}

- (NSTextField *)sectionLabel:(NSRect)frame text:(NSString *)text {
    NSTextField *label = [self label:frame text:text];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSTextField *)valueLabel:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = @"";
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.alignment = NSTextAlignmentRight;
    label.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    label.textColor = [NSColor labelColor];
    return label;
}

- (NSButton *)actionButton:(NSRect)frame title:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    button.target = self;
    button.action = action;
    return button;
}

- (void)refreshVisualMode {
    if (!self.visualView) return;
    self.visualView.equation = self.equationField.stringValue;
}

- (void)updateValueLabels {
    double pitchRatio = atomic_load_explicit(&g_synth.target_pitch, memory_order_relaxed);
    double tempo = atomic_load_explicit(&g_synth.target_tempo, memory_order_relaxed);
    double semitones = 12.0 * log2(pitchRatio <= 0.0 ? 1.0 : pitchRatio);
    self.pitchValue.stringValue = [NSString stringWithFormat:@"%+.2f st", semitones];
    self.tempoValue.stringValue = [NSString stringWithFormat:@"x%.3f", tempo];
    int aNow = (int)llround(atomic_load_explicit(&g_synth.macro_a, memory_order_relaxed));
    int bNow = (int)llround(atomic_load_explicit(&g_synth.macro_b, memory_order_relaxed));
    int cNow = (int)llround(atomic_load_explicit(&g_synth.macro_c, memory_order_relaxed));
    int dNow = (int)llround(atomic_load_explicit(&g_synth.macro_d, memory_order_relaxed));
    self.aValue.stringValue = [NSString stringWithFormat:@"%d", aNow];
    self.bValue.stringValue = [NSString stringWithFormat:@"%d", bNow];
    self.cValue.stringValue = [NSString stringWithFormat:@"%d", cNow];
    self.dValue.stringValue = [NSString stringWithFormat:@"%d", dNow];
    int shiftNow = (int)llround(atomic_load_explicit(&g_synth.macro_shift, memory_order_relaxed));
    int maskNow = (int)llround(atomic_load_explicit(&g_synth.macro_mask, memory_order_relaxed));
    self.shiftValue.stringValue = [NSString stringWithFormat:@"%d", shiftNow];
    self.maskValue.stringValue = [NSString stringWithFormat:@"%d", maskNow];

    [self refreshVisualization];
    [self refreshVisualMode];
}

- (double)configureSlider:(NSSlider *)slider
                      min:(double)min
                      max:(double)max
                    value:(double)value {
    slider.minValue = min;
    slider.maxValue = max;
    if (value < slider.minValue) value = slider.minValue;
    if (value > slider.maxValue) value = slider.maxValue;
    slider.doubleValue = value;
    return value;
}

- (void)applyMacroSliderRanges {
    double a = atomic_load_explicit(&g_synth.macro_a, memory_order_relaxed);
    double b = atomic_load_explicit(&g_synth.macro_b, memory_order_relaxed);
    double c = atomic_load_explicit(&g_synth.macro_c, memory_order_relaxed);
    double d = atomic_load_explicit(&g_synth.macro_d, memory_order_relaxed);
    double sh = floor(atomic_load_explicit(&g_synth.macro_shift, memory_order_relaxed) + 0.5);
    double mask = floor(atomic_load_explicit(&g_synth.macro_mask, memory_order_relaxed) + 0.5);

    a = floor([self configureSlider:self.aSlider min:-16.0 max:16.0 value:a] + 0.5);
    b = floor([self configureSlider:self.bSlider min:-16.0 max:16.0 value:b] + 0.5);
    c = floor([self configureSlider:self.cSlider min:-16.0 max:16.0 value:c] + 0.5);
    d = floor([self configureSlider:self.dSlider min:-16.0 max:16.0 value:d] + 0.5);
    sh = [self configureSlider:self.shiftSlider min:0.0 max:12.0 value:sh];
    mask = [self configureSlider:self.maskSlider min:0.0 max:127.0 value:mask];
    self.aSlider.doubleValue = a;
    self.bSlider.doubleValue = b;
    self.cSlider.doubleValue = c;
    self.dSlider.doubleValue = d;

    atomic_store_explicit(&g_synth.macro_a, a, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_b, b, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_c, c, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_d, d, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_shift, sh, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_mask, mask, memory_order_relaxed);
}

- (void)refreshVisualization {
    if (!self.macroViz || !self.waveViz) return;

    double a = atomic_load_explicit(&g_synth.macro_a, memory_order_relaxed);
    double b = atomic_load_explicit(&g_synth.macro_b, memory_order_relaxed);
    double c = atomic_load_explicit(&g_synth.macro_c, memory_order_relaxed);
    double d = atomic_load_explicit(&g_synth.macro_d, memory_order_relaxed);
    double sh = floor(atomic_load_explicit(&g_synth.macro_shift, memory_order_relaxed) + 0.5);
    double mask = floor(atomic_load_explicit(&g_synth.macro_mask, memory_order_relaxed) + 0.5);

    self.macroViz.a = a;
    self.macroViz.b = b;
    self.macroViz.c = c;
    self.macroViz.d = d;
    self.macroViz.sh = sh;
    self.macroViz.mask = mask;
    [self.macroViz setNeedsDisplay:YES];

    float samples[256] = {0};
    const int sampleCount = 256;
    double tempo = atomic_load_explicit(&g_synth.target_tempo, memory_order_relaxed);
    double pitch = atomic_load_explicit(&g_synth.target_pitch, memory_order_relaxed);
    double base = g_synth.timeline;
    double step = fmax(1.0, tempo * 12.0);

    pthread_mutex_lock(&g_synth.expr_lock);
    Expr *expr = g_synth.expr;
    EvalContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.a = a;
    ctx.b = b;
    ctx.c = c;
    ctx.d = d;
    ctx.sh = sh;
    ctx.mask = mask;
    for (int i = 0; i < sampleCount; ++i) {
        ctx.t = floor((base + i * step) * pitch);
        double y = expr ? expr_eval(expr, &ctx) : 0.0;
        samples[i] = bytebeat_to_float(y);
    }
    pthread_mutex_unlock(&g_synth.expr_lock);

    [self.waveViz updateWithSamples:samples count:sampleCount];
}

- (void)vizTick:(NSTimer *)timer {
    (void)timer;
    [self refreshVisualization];
}

- (void)macroChanged:(id)sender {
    (void)sender;
    double a = floor(self.aSlider.doubleValue + 0.5);
    double b = floor(self.bSlider.doubleValue + 0.5);
    double c = floor(self.cSlider.doubleValue + 0.5);
    double d = floor(self.dSlider.doubleValue + 0.5);
    self.aSlider.doubleValue = a;
    self.bSlider.doubleValue = b;
    self.cSlider.doubleValue = c;
    self.dSlider.doubleValue = d;
    atomic_store_explicit(&g_synth.macro_a, a, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_b, b, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_c, c, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_d, d, memory_order_relaxed);

    double shift = floor(self.shiftSlider.doubleValue + 0.5);
    double mask = floor(self.maskSlider.doubleValue + 0.5);
    self.shiftSlider.doubleValue = shift;
    self.maskSlider.doubleValue = mask;
    atomic_store_explicit(&g_synth.macro_shift, shift, memory_order_relaxed);
    atomic_store_explicit(&g_synth.macro_mask, mask, memory_order_relaxed);
    [self updateValueLabels];
}

- (void)applyEquation:(id)sender {
    (void)sender;
    NSString *eq = self.equationField.stringValue;
    if (set_expr(&g_synth, eq.UTF8String)) {
        g_synth.current_preset = -1;
        [self.presetPopup selectItemAtIndex:-1];
        [self updateValueLabels];
    } else {
        NSBeep();
    }
}

- (void)selectPreset:(NSInteger)idx {
    if (idx < 0 || idx >= PRESET_COUNT) return;
    set_preset(&g_synth, (int)idx);
    [self.presetPopup selectItemAtIndex:idx];
    self.equationField.stringValue = [NSString stringWithUTF8String:kPresets[idx].js];
    [self updateValueLabels];
}

- (void)presetChanged:(id)sender {
    [self selectPreset:self.presetPopup.indexOfSelectedItem];
    (void)sender;
}

- (void)nextPreset:(id)sender {
    (void)sender;
    NSInteger idx = g_synth.current_preset;
    if (idx < 0) idx = 0;
    idx = (idx + 1) % PRESET_COUNT;
    [self selectPreset:idx];
}

- (void)openAudioSettings:(id)sender {
    (void)sender;
    NSURL *audioMidiAppURL = [NSURL fileURLWithPath:@"/System/Applications/Utilities/Audio MIDI Setup.app"];
    BOOL opened = [[NSWorkspace sharedWorkspace] openURL:audioMidiAppURL];
    if (!opened) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleInformational;
        alert.messageText = @"Could not open Audio MIDI Setup automatically.";
        alert.informativeText = @"Open System Settings > Sound to change output/input devices.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}

- (void)exportWav:(id)sender {
    (void)sender;

    NSAlert *durAlert = [[NSAlert alloc] init];
    durAlert.alertStyle = NSAlertStyleInformational;
    durAlert.messageText = @"Export Normalized WAV";
    durAlert.informativeText = @"Enter duration in seconds.";
    [durAlert addButtonWithTitle:@"Continue"];
    [durAlert addButtonWithTitle:@"Cancel"];

    NSTextField *durField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)];
    durField.stringValue = @"10";
    durField.placeholderString = @"Seconds (e.g. 10)";
    durAlert.accessoryView = durField;

    NSModalResponse durResp = [durAlert runModal];
    if (durResp != NSAlertFirstButtonReturn) return;

    double durationSec = durField.doubleValue;
    if (!(durationSec > 0.0) || durationSec > 600.0) {
        NSAlert *bad = [[NSAlert alloc] init];
        bad.alertStyle = NSAlertStyleWarning;
        bad.messageText = @"Invalid duration";
        bad.informativeText = @"Duration must be between 0 and 600 seconds.";
        [bad addButtonWithTitle:@"OK"];
        [bad runModal];
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Export Normalized WAV";
    panel.nameFieldStringValue = @"bytebeat_export.wav";
    panel.allowedFileTypes = @[@"wav"];
    panel.canCreateDirectories = YES;
    if ([panel runModal] != NSModalResponseOK) return;

    uint32_t frameCount = (uint32_t)llround(durationSec * (double)SAMPLE_RATE);
    if (frameCount == 0) frameCount = 1;

    float *tmp = (float *)malloc(sizeof(float) * (size_t)frameCount);
    int16_t *pcm = (int16_t *)malloc(sizeof(int16_t) * (size_t)frameCount);
    if (!tmp || !pcm) {
        free(tmp);
        free(pcm);
        NSAlert *oom = [[NSAlert alloc] init];
        oom.alertStyle = NSAlertStyleCritical;
        oom.messageText = @"Export failed";
        oom.informativeText = @"Not enough memory for export buffer.";
        [oom addButtonWithTitle:@"OK"];
        [oom runModal];
        return;
    }

    Expr *expr = NULL;
    pthread_mutex_lock(&g_synth.expr_lock);
    expr = g_synth.expr;
    pthread_mutex_unlock(&g_synth.expr_lock);

    EvalContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.a = atomic_load_explicit(&g_synth.macro_a, memory_order_relaxed);
    ctx.b = atomic_load_explicit(&g_synth.macro_b, memory_order_relaxed);
    ctx.c = atomic_load_explicit(&g_synth.macro_c, memory_order_relaxed);
    ctx.d = atomic_load_explicit(&g_synth.macro_d, memory_order_relaxed);
    ctx.sh = floor(atomic_load_explicit(&g_synth.macro_shift, memory_order_relaxed) + 0.5);
    ctx.mask = floor(atomic_load_explicit(&g_synth.macro_mask, memory_order_relaxed) + 0.5);

    double tempo = atomic_load_explicit(&g_synth.target_tempo, memory_order_relaxed);
    double pitch = atomic_load_explicit(&g_synth.target_pitch, memory_order_relaxed);
    if (tempo <= 0.0) tempo = 1.0;
    if (pitch <= 0.0) pitch = 1.0;

    double timeline = 0.0;
    double peak = 0.0;
    for (uint32_t i = 0; i < frameCount; ++i) {
        timeline += tempo;
        ctx.t = floor(timeline * pitch);
        double y = expr ? expr_eval(expr, &ctx) : 0.0;
        float s = bytebeat_to_float(y);
        tmp[i] = s;
        double a = fabs((double)s);
        if (a > peak) peak = a;
    }

    double gain = (peak > 1e-9) ? (0.98 / peak) : 1.0;
    for (uint32_t i = 0; i < frameCount; ++i) {
        double v = (double)tmp[i] * gain;
        if (v > 1.0) v = 1.0;
        if (v < -1.0) v = -1.0;
        pcm[i] = (int16_t)lrint(v * 32767.0);
    }

    BOOL wrote = write_wav16_mono(panel.URL.fileSystemRepresentation, pcm, frameCount, SAMPLE_RATE);
    free(tmp);
    free(pcm);

    if (!wrote) {
        NSAlert *err = [[NSAlert alloc] init];
        err.alertStyle = NSAlertStyleCritical;
        err.messageText = @"Export failed";
        err.informativeText = @"Could not write WAV file to selected destination.";
        [err addButtonWithTitle:@"OK"];
        [err runModal];
        return;
    }

    self.statusLabel.stringValue = [NSString stringWithFormat:@"Exported %.2fs normalized WAV.", durationSec];
}

- (void)prevPreset:(id)sender {
    (void)sender;
    NSInteger idx = g_synth.current_preset;
    if (idx < 0) idx = 0;
    idx = (idx - 1 + PRESET_COUNT) % PRESET_COUNT;
    [self selectPreset:idx];
}

- (void)pitchChanged:(id)sender {
    (void)sender;
    double semitones = self.pitchSlider.doubleValue;
    double ratio = pow(2.0, semitones / 12.0);
    atomic_store_explicit(&g_synth.target_pitch, ratio, memory_order_relaxed);
    [self updateValueLabels];
}

- (void)tempoChanged:(id)sender {
    (void)sender;
    double tempo = self.tempoSlider.doubleValue;
    atomic_store_explicit(&g_synth.target_tempo, tempo, memory_order_relaxed);
    [self updateValueLabels];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    NSRect frame = NSMakeRect(0, 0, 860, 900);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"NORA";
    self.window.backgroundColor = [NSColor windowBackgroundColor];
    [self.window center];

    NSView *content = self.window.contentView;

    [content addSubview:[self sectionLabel:NSMakeRect(20, 872, 260, 18) text:@"EQUATION MACRO MAP"]];
    self.visualView = [[EquationVisualView alloc] initWithFrame:NSMakeRect(20, 742, 820, 120)];
    self.visualView.wantsLayer = YES;
    self.visualView.layer.cornerRadius = 8.0;
    self.visualView.layer.borderWidth = 1.0;
    self.visualView.layer.borderColor = [NSColor colorWithCalibratedWhite:0.22 alpha:1.0].CGColor;
    [content addSubview:self.visualView];

    [content addSubview:[self sectionLabel:NSMakeRect(20, 724, 220, 18) text:@"WAVEFORM PREVIEW"]];
    self.waveViz = [[WavePreviewView alloc] initWithFrame:NSMakeRect(20, 654, 820, 64)];
    self.waveViz.wantsLayer = YES;
    self.waveViz.layer.cornerRadius = 8.0;
    self.waveViz.layer.borderWidth = 1.0;
    self.waveViz.layer.borderColor = [NSColor colorWithCalibratedWhite:0.2 alpha:1.0].CGColor;
    [content addSubview:self.waveViz];

    [content addSubview:[self sectionLabel:NSMakeRect(20, 628, 220, 18) text:@"MACRO ACTIVITY"]];
    self.macroViz = [[MacroVizView alloc] initWithFrame:NSMakeRect(20, 578, 820, 48)];
    self.macroViz.wantsLayer = YES;
    self.macroViz.layer.cornerRadius = 8.0;
    self.macroViz.layer.borderWidth = 1.0;
    self.macroViz.layer.borderColor = [NSColor colorWithCalibratedWhite:0.22 alpha:1.0].CGColor;
    [content addSubview:self.macroViz];

    [content addSubview:[self sectionLabel:NSMakeRect(20, 548, 180, 20) text:@"EQUATION (JS STYLE)"]];
    self.equationField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 516, 710, 28)];
    self.equationField.placeholderString = @"Example: ((t*a)&(t>>c))|((t*b)&(t>>d))";
    self.equationField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    [content addSubview:self.equationField];

    NSButton *applyButton = [self actionButton:NSMakeRect(740, 516, 100, 28)
                                         title:@"Apply"
                                        action:@selector(applyEquation:)];
    applyButton.keyEquivalent = @"\r";
    [content addSubview:applyButton];

    [content addSubview:[self sectionLabel:NSMakeRect(20, 470, 120, 20) text:@"PRESET"]];
    self.presetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 438, 360, 28) pullsDown:NO];
    for (int i = 0; i < PRESET_COUNT; ++i) {
        NSString *item = [NSString stringWithFormat:@"%2d. %s", i + 1, kPresets[i].name];
        [self.presetPopup addItemWithTitle:item];
    }
    self.presetPopup.target = self;
    self.presetPopup.action = @selector(presetChanged:);
    [content addSubview:self.presetPopup];

    NSButton *prevButton = [self actionButton:NSMakeRect(390, 438, 80, 28)
                                        title:@"Prev"
                                       action:@selector(prevPreset:)];
    [content addSubview:prevButton];

    NSButton *nextButton2 = [self actionButton:NSMakeRect(480, 438, 80, 28)
                                         title:@"Next"
                                        action:@selector(nextPreset:)];
    [content addSubview:nextButton2];

    NSButton *audioSettingsButton = [self actionButton:NSMakeRect(570, 438, 130, 28)
                                                 title:@"Audio Settings"
                                                action:@selector(openAudioSettings:)];
    [content addSubview:audioSettingsButton];

    NSButton *exportButton = [self actionButton:NSMakeRect(710, 438, 130, 28)
                                          title:@"Export WAV"
                                         action:@selector(exportWav:)];
    [content addSubview:exportButton];

    [content addSubview:[self sectionLabel:NSMakeRect(20, 392, 150, 20) text:@"PITCH (SEMITONES)"]];
    self.pitchSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 360, 720, 24)];
    self.pitchSlider.minValue = -24.0;
    self.pitchSlider.maxValue = 24.0;
    self.pitchSlider.doubleValue = 0.0;
    self.pitchSlider.target = self;
    self.pitchSlider.action = @selector(pitchChanged:);
    [content addSubview:self.pitchSlider];

    self.pitchValue = [self valueLabel:NSMakeRect(744, 362, 95, 20)];
    [content addSubview:self.pitchValue];

    [content addSubview:[self sectionLabel:NSMakeRect(20, 336, 160, 20) text:@"TEMPO MULTIPLIER"]];
    self.tempoSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 304, 720, 24)];
    self.tempoSlider.minValue = 0.05;
    self.tempoSlider.maxValue = 8.0;
    self.tempoSlider.doubleValue = 1.0;
    self.tempoSlider.target = self;
    self.tempoSlider.action = @selector(tempoChanged:);
    [content addSubview:self.tempoSlider];

    self.tempoValue = [self valueLabel:NSMakeRect(744, 306, 95, 20)];
    [content addSubview:self.tempoValue];

    NSTextField *macroALabel = [self sectionLabel:NSMakeRect(20, 280, 90, 20) text:@"MACRO A"];
    macroALabel.textColor = macro_color('a', 1.0);
    [content addSubview:macroALabel];
    self.aSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 252, 720, 24)];
    self.aSlider.minValue = -16.0;
    self.aSlider.maxValue = 16.0;
    self.aSlider.doubleValue = 5.0;
    self.aSlider.continuous = YES;
    self.aSlider.target = self;
    self.aSlider.action = @selector(macroChanged:);
    [content addSubview:self.aSlider];
    self.aValue = [self valueLabel:NSMakeRect(744, 254, 95, 20)];
    self.aValue.textColor = macro_color('a', 1.0);
    [content addSubview:self.aValue];

    NSTextField *macroBLabel = [self sectionLabel:NSMakeRect(20, 230, 90, 20) text:@"MACRO B"];
    macroBLabel.textColor = macro_color('b', 1.0);
    [content addSubview:macroBLabel];
    self.bSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 202, 720, 24)];
    self.bSlider.minValue = -16.0;
    self.bSlider.maxValue = 16.0;
    self.bSlider.doubleValue = 3.0;
    self.bSlider.continuous = YES;
    self.bSlider.target = self;
    self.bSlider.action = @selector(macroChanged:);
    [content addSubview:self.bSlider];
    self.bValue = [self valueLabel:NSMakeRect(744, 204, 95, 20)];
    self.bValue.textColor = macro_color('b', 1.0);
    [content addSubview:self.bValue];

    NSTextField *macroCLabel = [self sectionLabel:NSMakeRect(20, 180, 90, 20) text:@"MACRO C"];
    macroCLabel.textColor = macro_color('c', 1.0);
    [content addSubview:macroCLabel];
    self.cSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 152, 720, 24)];
    self.cSlider.minValue = -16.0;
    self.cSlider.maxValue = 16.0;
    self.cSlider.doubleValue = 7.0;
    self.cSlider.continuous = YES;
    self.cSlider.target = self;
    self.cSlider.action = @selector(macroChanged:);
    [content addSubview:self.cSlider];
    self.cValue = [self valueLabel:NSMakeRect(744, 154, 95, 20)];
    self.cValue.textColor = macro_color('c', 1.0);
    [content addSubview:self.cValue];

    NSTextField *macroDLabel = [self sectionLabel:NSMakeRect(20, 130, 90, 20) text:@"MACRO D"];
    macroDLabel.textColor = macro_color('d', 1.0);
    [content addSubview:macroDLabel];
    self.dSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 102, 720, 24)];
    self.dSlider.minValue = -16.0;
    self.dSlider.maxValue = 16.0;
    self.dSlider.doubleValue = 10.0;
    self.dSlider.continuous = YES;
    self.dSlider.target = self;
    self.dSlider.action = @selector(macroChanged:);
    [content addSubview:self.dSlider];
    self.dValue = [self valueLabel:NSMakeRect(744, 104, 95, 20)];
    self.dValue.textColor = macro_color('d', 1.0);
    [content addSubview:self.dValue];

    [content addSubview:[self sectionLabel:NSMakeRect(20, 62, 110, 20) text:@"SHIFT (SH)"]];
    self.shiftSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 46, 350, 20)];
    self.shiftSlider.minValue = 0.0;
    self.shiftSlider.maxValue = 12.0;
    self.shiftSlider.doubleValue = 8.0;
    self.shiftSlider.continuous = YES;
    self.shiftSlider.target = self;
    self.shiftSlider.action = @selector(macroChanged:);
    [content addSubview:self.shiftSlider];
    self.shiftValue = [self valueLabel:NSMakeRect(374, 46, 60, 20)];
    [content addSubview:self.shiftValue];

    [content addSubview:[self sectionLabel:NSMakeRect(460, 62, 110, 20) text:@"BITMASK"]];
    self.maskSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(460, 46, 280, 20)];
    self.maskSlider.minValue = 0.0;
    self.maskSlider.maxValue = 127.0;
    self.maskSlider.doubleValue = 127.0;
    self.maskSlider.continuous = YES;
    self.maskSlider.target = self;
    self.maskSlider.action = @selector(macroChanged:);
    [content addSubview:self.maskSlider];
    self.maskValue = [self valueLabel:NSMakeRect(744, 46, 95, 20)];
    [content addSubview:self.maskValue];

    set_slider_track_color(self.aSlider, macro_color('a', 1.0));
    set_slider_track_color(self.bSlider, macro_color('b', 1.0));
    set_slider_track_color(self.cSlider, macro_color('c', 1.0));
    set_slider_track_color(self.dSlider, macro_color('d', 1.0));

    self.statusLabel = [self label:NSMakeRect(20, 490, 760, 18) text:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    [content addSubview:self.statusLabel];

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
    g_synth.current_preset = 0;
    [self selectPreset:0];
    [self applyMacroSliderRanges];

    if (!audio_start(&g_synth)) {
        self.statusLabel.stringValue = @"Audio start failed. Check macOS audio output permissions/device.";
    }

    [self updateValueLabels];
    self.vizTimer = [NSTimer timerWithTimeInterval:(1.0 / 20.0)
                                            target:self
                                          selector:@selector(vizTick:)
                                          userInfo:nil
                                           repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.vizTimer forMode:NSRunLoopCommonModes];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.vizTimer invalidate];
    self.vizTimer = nil;
    atomic_store_explicit(&g_synth.running, false, memory_order_relaxed);
    audio_stop(&g_synth);

    pthread_mutex_lock(&g_synth.expr_lock);
    Expr *final_expr = g_synth.expr;
    g_synth.expr = NULL;
    pthread_mutex_unlock(&g_synth.expr_lock);
    expr_free(final_expr);
    pthread_mutex_destroy(&g_synth.expr_lock);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end

static NSMenu *buildMainMenu(void) {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"App" action:nil keyEquivalent:@""];
    [mainMenu addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App"];
    NSString *appName = [[NSProcessInfo processInfo] processName];
    NSString *quitTitle = [@"Quit " stringByAppendingString:appName];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];

    return mainMenu;
}

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        app.mainMenu = buildMainMenu();

        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
