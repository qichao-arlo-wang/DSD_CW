function results = task7a_cordic_mc(varargin)
%TASK7A_CORDIC_MC Monte-Carlo analysis for Task 7a CORDIC cosine.
%
% The sweep explores BOTH parameters requested in Task 7a:
%   - CORDIC iterations (n_iter)
%   - fixed-point fractional bits (FRAC), with total width W = FRAC + 2
%
% For each configuration this function reports:
%   - analytical estimate term 2^(-i), using i = n_iter
%   - Monte-Carlo MSE and 95% CI (normal approximation)
%   - pass/fail against the coursework limit
%
% requirement:
%   upper 95% CI bound of MSE < 2.4e-11, for theta ~ U[-1,1]
%   where theta is treated as single precision.
%
% Usage:
%   task7a_cordic_mc
%   task7a_cordic_mc('samples', 50000, 'seed', 7)
%   task7a_cordic_mc('export_csv', '/abs/path/t7a.csv')
%   task7a_cordic_mc('figure_dir', '/abs/path/report3/Images', ...
%                    'figure_prefix', 't7a')
%
% Output:
%   A struct with fields: .table, .best_score, .best_metrics, .mse_limit

    mse_limit = 2.4e-11;

    p = inputParser;
    addParameter(p, 'samples', 50000);
    addParameter(p, 'seed', 7);
    addParameter(p, 'iters', 12:24);
    addParameter(p, 'fracs', 20:34);
    addParameter(p, 'export_csv', '');
    addParameter(p, 'figure_dir', '');
    addParameter(p, 'figure_prefix', 't7a');
    parse(p, varargin{:});
    opts = p.Results;

    fprintf('CORDIC sweep for Task 7a\n');
    fprintf('Samples=%d, seed=%d, limit=%.3e\n', opts.samples, opts.seed, mse_limit);
    fprintf('iter W frac 2^-i_est mse ci95_low ci95_high pass\n');

    n_cfg = numel(opts.iters) * numel(opts.fracs);
    n_iter_col = zeros(n_cfg, 1);
    w_col = zeros(n_cfg, 1);
    frac_col = zeros(n_cfg, 1);
    est_2mi_col = zeros(n_cfg, 1);
    mse_col = zeros(n_cfg, 1);
    ci_lo_col = zeros(n_cfg, 1);
    ci_hi_col = zeros(n_cfg, 1);
    pass_col = false(n_cfg, 1);

    best_score = [];
    best_metrics = [];
    idx = 1;

    % Deterministic sweep. "Best" uses lexicographic order:
    % minimum n_iter first (latency), then minimum FRAC (resource).
    for frac = opts.fracs
        w = frac + 2;
        for n_iter = opts.iters
            [mse, ci_lo, ci_hi] = evaluate_cfg(n_iter, frac, opts.samples, opts.seed);
            est_2mi = 2.0^(-n_iter);
            passed = ci_hi < mse_limit;

            fprintf('%4d %2d %4d %.3e %.3e %.3e %.3e %s\n', ...
                n_iter, w, frac, est_2mi, mse, ci_lo, ci_hi, ternary(passed, 'YES', 'NO'));

            n_iter_col(idx) = n_iter;
            w_col(idx) = w;
            frac_col(idx) = frac;
            est_2mi_col(idx) = est_2mi;
            mse_col(idx) = mse;
            ci_lo_col(idx) = ci_lo;
            ci_hi_col(idx) = ci_hi;
            pass_col(idx) = passed;
            idx = idx + 1;

            if passed
                score = [n_iter, frac];
                if isempty(best_score) || lexicographically_less(score, best_score)
                    best_score = score;
                    best_metrics = [mse, ci_lo, ci_hi];
                end
            end
        end
    end

    tbl = table( ...
        n_iter_col, w_col, frac_col, est_2mi_col, mse_col, ci_lo_col, ci_hi_col, pass_col, ...
        'VariableNames', {'n_iter', 'W', 'FRAC', 'est_2m_i', 'mse', 'ci95_low', 'ci95_high', 'pass'});

    if ~isempty(opts.export_csv)
        ensure_parent_dir(opts.export_csv);
        writetable(tbl, opts.export_csv);
        fprintf('Wrote CSV: %s\n', opts.export_csv);
    end

    if ~isempty(opts.figure_dir)
        ensure_dir(opts.figure_dir);
        generate_figures(tbl, mse_limit, opts.figure_dir, opts.figure_prefix);
    end

    if isempty(best_score)
        fprintf('\nNo configuration met the target bound.\n');
    else
        fprintf('\nBest passing configuration (minimum iterations, then minimum FRAC):\n');
        fprintf('n_iter=%d, W=%d, frac=%d, mse=%.3e, ci95=[%.3e, %.3e]\n', ...
            best_score(1), best_score(2) + 2, best_score(2), best_metrics(1), best_metrics(2), best_metrics(3));
    end

    results = struct( ...
        'table', tbl, ...
        'best_score', best_score, ...
        'best_metrics', best_metrics, ...
        'mse_limit', mse_limit);
end

function [mse, ci_lo, ci_hi] = evaluate_cfg(n_iter, frac, n_samples, seed)
% Evaluate one (n_iter, frac) CORDIC configuration.
%
% Seed is reset for each configuration to keep sampling identical across
% sweep points, isolating architecture effects from RNG variability.

    rng(seed, 'twister');
    sq_err = zeros(n_samples, 1);

    for k = 1:n_samples
        % Coursework distribution and precision:
        % theta ~ U[-1,1] under single-precision representation.
        theta_sp = single(-1.0 + 2.0 * rand());
        theta = double(theta_sp);

        % Reference is MATLAB single-precision cosine.
        ref = double(single(cos(theta_sp)));

        % Estimate uses fixed-point CORDIC and returns float value.
        est = cordic_cos(theta, n_iter, frac);

        d = est - ref;
        sq_err(k) = d * d;
    end

    [mse, ci_lo, ci_hi] = mse_with_ci(sq_err);
end

function [mean_v, ci_lo, ci_hi] = mse_with_ci(samples)
% Return sample mean and normal-approximation 95% CI for the mean.
%
% CI formula:
%   mean +/- 1.96 * s / sqrt(n)
% where s is sample standard deviation (N-1 normalization).

    n = numel(samples);
    mean_v = mean(samples);

    if n < 2
        ci_lo = mean_v;
        ci_hi = mean_v;
        return;
    end

    stdev_v = std(samples, 0);
    half = 1.96 * stdev_v / sqrt(double(n));
    ci_lo = mean_v - half;
    ci_hi = mean_v + half;
end

function cos_est = cordic_cos(theta, n_iter, frac)
% Fixed-point rotation-mode CORDIC cosine approximation.
%
% Implementation notes:
% - preload x with inverse CORDIC gain K_n
% - use integer arithmetic + arithmetic right shifts
% - iterate n_iter times with atan(2^-i) table

    scale = int64(2^frac);

    % Inverse CORDIC gain: after n_iter rotations, x approximates cos(theta).
    k_gain = 1.0;
    for i = 0:(n_iter - 1)
        k_gain = k_gain * (1.0 / sqrt(1.0 + 2.0^(-2 * i)));
    end

    % Fixed-point state (x, y, z), where z is residual angle.
    x = int64(round(k_gain * double(scale)));
    y = int64(0);
    z = int64(round(theta * double(scale)));

    % atan LUT in the same fixed-point scale as z.
    atan_table = zeros(1, n_iter, 'int64');
    for i = 0:(n_iter - 1)
        atan_table(i + 1) = int64(round(atan(2.0^(-i)) * double(scale)));
    end

    for i = 0:(n_iter - 1)
        if z >= 0
            x_next = x - bitshift(y, -i);
            y_next = y + bitshift(x, -i);
            z_next = z - atan_table(i + 1);
        else
            x_next = x + bitshift(y, -i);
            y_next = y - bitshift(x, -i);
            z_next = z + atan_table(i + 1);
        end

        x = x_next;
        y = y_next;
        z = z_next;
    end

    cos_est = double(x) / double(scale);
end

function generate_figures(tbl, mse_limit, out_dir, prefix)
% Generate report-ready figures for Task 7a.
%
% Figure 1:
%   95% CI upper bound versus iterations (log scale):
%   top panel full sweep, bottom panel zoomed panel for n_iter >= 16.
% Figure 2:
%   Analytical estimate 2^{-i} versus observed error scale for selected FRAC,
%   shown as log10 values for improved visual separation in two-column PDFs.

    ax_font = 15;
    title_font = 17;
    legend_font = 12;
    line_w = 1.5;
    mark_sz = 7;

    fig1 = figure('Visible', 'off', 'Position', [100 100 1100 900]);
    t = tiledlayout(fig1, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    fracs = unique(tbl.FRAC)';

    % ---- Panel 1: full sweep trend (log-y)
    ax1 = nexttile(t, 1);
    hold(ax1, 'on');
    for frac = fracs
        m = (tbl.FRAC == frac);
        sub = sortrows(tbl(m, :), 'n_iter');
        semilogy(ax1, sub.n_iter, sub.ci95_high, '-o', ...
            'LineWidth', line_w, 'MarkerSize', mark_sz, ...
            'DisplayName', sprintf('FRAC=%d', frac));
    end
    yline(ax1, mse_limit, '--r', 'LineWidth', 1.8, ...
        'DisplayName', sprintf('Target %.2e', mse_limit));
    grid(ax1, 'on');
    xlabel(ax1, 'CORDIC iterations (n_{iter})', 'FontSize', ax_font, 'FontWeight', 'bold');
    ylabel(ax1, '95% CI upper bound (MSE)', 'FontSize', ax_font, 'FontWeight', 'bold');
    title(ax1, 'Task 7a full trend (log scale)', 'FontSize', title_font, 'FontWeight', 'bold');
    set(ax1, 'FontSize', ax_font, 'LineWidth', 1.1, 'XLim', [min(tbl.n_iter)-0.5, max(tbl.n_iter)+0.5]);
    legend(ax1, 'Location', 'northeast', 'FontSize', legend_font);
    hold(ax1, 'off');

    % ---- Panel 2: zoomed view for n_iter >= 16 (log-y)
    ax2 = nexttile(t, 2);
    hold(ax2, 'on');
    zoom_mask = (tbl.n_iter >= 16);
    zoom_vals = tbl.ci95_high(zoom_mask);
    for frac = fracs
        m = (tbl.FRAC == frac) & (tbl.n_iter >= 16);
        sub = sortrows(tbl(m, :), 'n_iter');
        semilogy(ax2, sub.n_iter, sub.ci95_high, '-o', ...
            'LineWidth', line_w, 'MarkerSize', mark_sz, ...
            'DisplayName', sprintf('FRAC=%d', frac));
    end
    yline(ax2, mse_limit, '--r', 'LineWidth', 1.8, ...
        'DisplayName', sprintf('Target %.2e', mse_limit));
    grid(ax2, 'on');
    xlabel(ax2, 'CORDIC iterations (n_{iter})', 'FontSize', ax_font, 'FontWeight', 'bold');
    ylabel(ax2, '95% CI upper bound (MSE)', 'FontSize', ax_font, 'FontWeight', 'bold');
    title(ax2, 'Zoomed trend for n_{iter} \geq 16 (log scale)', 'FontSize', title_font, 'FontWeight', 'bold');
    set(ax2, 'FontSize', ax_font, 'LineWidth', 1.1, 'XLim', [16 24], ...
        'YLim', [min(zoom_vals)*0.8, max(zoom_vals)*1.25]);
    hold(ax2, 'off');

    out1 = fullfile(out_dir, sprintf('%s_ci_upper_vs_iter.png', prefix));
    exportgraphics(fig1, out1, 'Resolution', 280);
    close(fig1);
    fprintf('Wrote figure: %s\n', out1);

    fig2 = figure('Visible', 'off', 'Position', [100 100 1000 620]);
    pass_fracs = unique(tbl.FRAC(tbl.pass))';
    if isempty(pass_fracs)
        sel_frac = min(fracs);
    else
        sel_frac = min(pass_fracs);
    end

    m = (tbl.FRAC == sel_frac);
    sub = sortrows(tbl(m, :), 'n_iter');
    hold on;
    plot(sub.n_iter, log10(sub.est_2m_i), '-s', ...
        'LineWidth', line_w, 'MarkerSize', mark_sz, ...
        'DisplayName', 'Analytical estimate 2^{-i}');
    plot(sub.n_iter, log10(sqrt(sub.mse)), '-o', ...
        'LineWidth', line_w, 'MarkerSize', mark_sz, ...
        'DisplayName', 'Observed RMS error sqrt(MSE)');
    plot(sub.n_iter, log10(sqrt(sub.ci95_high)), '--^', ...
        'LineWidth', line_w, 'MarkerSize', mark_sz, ...
        'DisplayName', 'Upper 95% bound (sqrt(CI_high))');
    grid on;
    xlabel('CORDIC iterations (n_{iter})', 'FontSize', ax_font, 'FontWeight', 'bold');
    ylabel('log_{10}(error scale)', 'FontSize', ax_font, 'FontWeight', 'bold');
    title(sprintf('Task 7a analytical vs MC trend (FRAC=%d, log_{10} scale)', sel_frac), ...
        'FontSize', title_font, 'FontWeight', 'bold');
    set(gca, 'FontSize', ax_font, 'LineWidth', 1.1, 'XLim', [min(sub.n_iter)-0.5, max(sub.n_iter)+0.5]);
    legend('Location', 'northeast', 'FontSize', legend_font);
    hold off;
    out2 = fullfile(out_dir, sprintf('%s_error_estimate_vs_mc.png', prefix));
    exportgraphics(fig2, out2, 'Resolution', 280);
    close(fig2);
    fprintf('Wrote figure: %s\n', out2);
end

function tf = lexicographically_less(lhs_score, rhs_score)
% Lexicographic order helper for [n_iter, frac].

    if lhs_score(1) < rhs_score(1)
        tf = true;
    elseif lhs_score(1) > rhs_score(1)
        tf = false;
    else
        tf = lhs_score(2) < rhs_score(2);
    end
end

function out = ternary(cond, a, b)
% Small helper to keep table-printing line compact.
    if cond
        out = a;
    else
        out = b;
    end
end

function ensure_dir(path_str)
% Create directory if it does not exist.
    if ~isfolder(path_str)
        mkdir(path_str);
    end
end

function ensure_parent_dir(file_path)
% Ensure parent directory exists before writing files.
    parent = fileparts(file_path);
    if ~isempty(parent)
        ensure_dir(parent);
    end
end
