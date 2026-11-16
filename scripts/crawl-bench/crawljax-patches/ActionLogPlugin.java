package com.crawljax.examples;

import com.crawljax.core.CrawlerContext;
import com.crawljax.core.plugin.OnNewStatePlugin;
import com.crawljax.core.plugin.OnRevisitStatePlugin;
import com.crawljax.core.state.Eventable;
import com.crawljax.core.state.StateVertex;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;

/**
 * CrawlBench: logs every state transition decided by the SAF to a JSON-lines file, so that coverage (which is
 * recorded separately with timestamps) can later be attributed to the state/action that caused it.
 *
 * One line per action outcome: wall-clock time (epoch ms, same clock as the PHP coverage dumps), crawl-relative time,
 * whether the SAF judged the reached state NEW or a REVISIT (duplicate), the reached state, the state the action
 * was fired from and the action itself.
 */
public class ActionLogPlugin implements OnNewStatePlugin, OnRevisitStatePlugin {
    private final PrintWriter out;
    private final long startMs = System.currentTimeMillis();
    private long seq = 0;

    public ActionLogPlugin(File outputDir) {
        try {
            outputDir.mkdirs();
            out = new PrintWriter(new FileWriter(new File(outputDir, "action-log.jsonl"), true), true);
        } catch (IOException e) {
            throw new IllegalStateException("cannot open action log", e);
        }
        write("{\"event\":\"START\",\"t_ms\":" + startMs + "}");
    }

    @Override
    public void onNewState(CrawlerContext context, StateVertex newState) {
        log("NEW", context, newState);
    }

    @Override
    public void onRevisitState(CrawlerContext context, StateVertex currentState) {
        log("REVISIT", context, currentState);
    }

    private synchronized void log(String kind, CrawlerContext context, StateVertex state) {
        long now = System.currentTimeMillis();
        String from = "", action = "", type = "", id = "", err = "";
        int depth = 0;
        try {
            try { depth = context.getCrawlPath().size(); } catch (Exception noPath) { /* path not set yet */ }
            Eventable e = context.getLastEventable();
            if (e != null) {
                if (e.getSourceStateVertex() != null) from = e.getSourceStateVertex().getName();
                if (e.getIdentification() != null) action = e.getIdentification().getValue();
                if (e.getEventType() != null) type = e.getEventType().toString();
                id = Long.toString(e.getId());
            }
        } catch (Exception ex) { err = ex.toString(); }
        String evKind = context.getLastEventKind();
        String url = "";
        try { url = context.getBrowser().getCurrentUrl(); } catch (Exception ignored) { }
        write("{\"seq\":" + (seq++) + ",\"event\":\"" + kind + "\",\"t_ms\":" + now + ",\"elapsed_ms\":" + (now - startMs)
                + ",\"kind\":" + q(evKind) + ",\"state\":" + q(state.getName()) + ",\"from\":" + q(from) + ",\"action\":" + q(action)
                + ",\"action_type\":" + q(type) + ",\"action_id\":" + q(id) + ",\"err\":" + q(err) + ",\"depth\":" + depth
                + ",\"url\":" + q(url) + "}");
    }

    private void write(String line) { out.println(line); }

    private static String q(String s) {
        if (s == null) return "\"\"";
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").replace("\r", " ") + "\"";
    }
}
