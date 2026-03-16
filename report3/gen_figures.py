import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

# ── Data ─────────────────────────────────────────────────────────────────────
labels   = ['R2-V6\n(baseline)', 'T7-S2\n(CORDIC)', 'T7-S3\n(single CI)', 'T8-V1\n(accum CI)', 'T8-V2\n(pipeline)']
latency  = [4380, 824, 220, 133, 75]
alms     = [2103, 3767, 3795, 3793, 13955]
dsps     = [6, 1, 1, 1, 18]
colors   = ['#4C72B0', '#DD8452', '#55A868', '#C44E52', '#8172B2']

baseline_lat  = latency[0]
baseline_alms = alms[0]
speedups      = [baseline_lat / l for l in latency]
extra_alms    = [a - baseline_alms for a in alms]

# ── Figure 1: Bar + ALMs (right axis) + DSPs (second right axis) ─────────────
fig1, ax1 = plt.subplots(figsize=(7.5, 4.2))
x = np.arange(len(labels))
bars = ax1.bar(x, latency, color=colors, width=0.55, zorder=2)

for bar, lat in zip(bars, latency):
    ax1.text(bar.get_x() + bar.get_width() / 2,
             bar.get_height() + 60,
             f'{lat:,} ms', ha='center', va='bottom', fontsize=8.5, fontweight='bold')

ax1.set_ylabel('C3 Latency (ms)', fontsize=10)
ax1.set_xticks(x)
ax1.set_xticklabels(labels, fontsize=9)
ax1.set_ylim(0, max(latency) * 1.18)
ax1.yaxis.set_major_formatter(ticker.FuncFormatter(lambda v, _: f'{int(v):,}'))
ax1.grid(axis='y', linestyle='--', alpha=0.4, zorder=0)
ax1.set_title('C3 Latency and Resource Usage Across Variants', fontsize=11, fontweight='bold')

# Right axis 1: ALMs
ax2 = ax1.twinx()
ax2.plot(x, alms, color='#7B2D8B', marker='s', linewidth=1.8,
         markersize=6, label='ALMs', zorder=3)
for xi, a in zip(x, alms):
    ax2.annotate(f'{a:,}', xy=(xi, a),
                 xytext=(0, 8), textcoords='offset points',
                 ha='center', fontsize=7.5, color='#7B2D8B')
ax2.set_ylabel('ALMs', fontsize=10, color='#7B2D8B')
ax2.tick_params(axis='y', colors='#7B2D8B')
ax2.set_ylim(0, max(alms) * 1.3)
ax2.yaxis.set_major_formatter(ticker.FuncFormatter(lambda v, _: f'{int(v):,}'))

# Right axis 2: DSPs (offset outward)
ax3 = ax1.twinx()
ax3.spines['right'].set_position(('outward', 70))
ax3.plot(x, dsps, color='#E67E22', marker='^', linewidth=1.5,
         markersize=6, linestyle='--', label='DSP blocks', zorder=4)
for xi, d in zip(x, dsps):
    ax3.annotate(f'{d}', xy=(xi, d),
                 xytext=(0, 7), textcoords='offset points',
                 ha='center', fontsize=7.5, color='#E67E22')
ax3.set_ylabel('DSP Blocks', fontsize=10, color='#E67E22')
ax3.tick_params(axis='y', colors='#E67E22')
ax3.set_ylim(0, max(dsps) * 3.5)
ax3.yaxis.set_major_locator(ticker.MaxNLocator(integer=True))

# Combined legend
lines2, labels2 = ax2.get_legend_handles_labels()
lines3, labels3 = ax3.get_legend_handles_labels()
ax2.legend(lines2 + lines3, labels2 + labels3, loc='upper left', fontsize=8.5)

fig1.tight_layout()
fig1.savefig('Images/r3_latency_alms.png', dpi=200, bbox_inches='tight')
print("Saved: Images/r3_latency_alms.png")

# ── Figure 2: Speedup vs additional ALMs, DSP encoded as marker size ──────────
fig2, ax4 = plt.subplots(figsize=(6.5, 4.2))

# Marker size: base 80 + DSP * 12
sizes = [80 + d * 12 for d in dsps]

for i, (ea, sp, lab, col, sz, d) in enumerate(
        zip(extra_alms, speedups, labels, colors, sizes, dsps)):
    ax4.scatter(ea, sp, s=sz, color=col, zorder=3, edgecolors='white', linewidth=0.8)
    short = lab.replace('\n', ' ')
    if i == 4:
        offset, ha = (-12, 5), 'right'
    elif i == 3:
        offset, ha = (12, -14), 'left'
    else:
        offset, ha = (12, 5), 'left'
    ax4.annotate(f'{short}\n({sp:.1f}×, DSP={d})',
                 xy=(ea, sp), xytext=offset,
                 textcoords='offset points',
                 fontsize=8, ha=ha, va='bottom')

# Arrow S2→S3
ax4.annotate('', xy=(extra_alms[2], speedups[2]),
             xytext=(extra_alms[1], speedups[1]),
             arrowprops=dict(arrowstyle='->', color='gray', linestyle='dashed', lw=1.2))
ax4.text((extra_alms[1]+extra_alms[2])/2 + 120,
         (speedups[1]+speedups[2])/2,
         'fn-level CI\n+28 ALMs, ×3.7', fontsize=7.5, color='gray', ha='left')

# Arrow V1→V2
ax4.annotate('', xy=(extra_alms[4], speedups[4]),
             xytext=(extra_alms[3], speedups[3]),
             arrowprops=dict(arrowstyle='->', color='gray', linestyle='dashed', lw=1.2))
ax4.text((extra_alms[3]+extra_alms[4])/2 - 600,
         (speedups[3]+speedups[4])/2 + 1.5,
         'pipeline\n+10162 ALMs\n+17 DSPs, ×1.77', fontsize=7.5, color='gray', ha='right')

# DSP size legend
for d_val, label in [(1, 'DSP=1'), (6, 'DSP=6'), (18, 'DSP=18')]:
    ax4.scatter([], [], s=80 + d_val*12, color='gray', alpha=0.6, label=label)
ax4.legend(title='Marker size ∝ DSP', fontsize=8, title_fontsize=8,
           loc='upper left', framealpha=0.7)

ax4.set_xlabel('Additional ALMs (relative to R2-V6)', fontsize=10)
ax4.set_ylabel('Speedup (relative to R2-V6, C3)', fontsize=10)
ax4.set_title('Speedup vs Resource Cost', fontsize=11, fontweight='bold')
ax4.grid(linestyle='--', alpha=0.4)
ax4.set_xlim(-800, max(extra_alms) * 1.18)
ax4.set_ylim(0, max(speedups) * 1.2)

fig2.tight_layout()
fig2.savefig('Images/r3_speedup_alms.png', dpi=200, bbox_inches='tight')
print("Saved: Images/r3_speedup_alms.png")
