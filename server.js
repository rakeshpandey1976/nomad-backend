import express from "express";
import cors from "cors";
import crypto from "crypto";
import pg from "pg";

const { Pool } = pg;

const app = express();
app.use(cors());
app.use(express.json());

const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error("DATABASE_URL is not set.");
  process.exit(1);
}

const pool = new Pool({
  connectionString: DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const recipes = {
  pilaf: {
    id: "pilaf",
    title: "Bottle Gourd Rice Pilaf",
    mode: "Inspired",
    reason: "A light, practical dish for an everyday kitchen.",
    time: "30 min",
    note: "This draws from a gentle home-style lauki chawal logic.",
    phases: [
      "Prep the ingredients evenly",
      "Bloom cumin and soften onion",
      "Cook down the bottle gourd",
      "Fold in the rice gently and finish",
    ],
    steps: [
      { instruction: "Wash and cut the bottle gourd into small cubes.", cue: "Pieces should be small and fairly even.", caution: "" },
      { instruction: "Warm a little oil, add cumin, then soften the onion gently.", cue: "You want fragrance and softening, not deep browning.", caution: "If the cumin darkens too fast, lower the heat." },
      { instruction: "Add the bottle gourd and cook until the pan looks less watery.", cue: "The vegetable should look softer and less wet.", caution: "Do not add extra water too early." },
      { instruction: "Fold in the rice gently and finish with salt to taste.", cue: "The rice should stay separate rather than mashed.", caution: "" },
    ],
  },
  traditional: {
    id: "traditional",
    title: "Lauki Chawal, Home-Style",
    mode: "Traditional",
    reason: "A calmer household direction with a familiar cooking logic.",
    time: "35 min",
    note: "This stays closer to a simple, traditional everyday preparation.",
    phases: [
      "Cut and prepare the gourd",
      "Cook the base gently",
      "Add and soften the vegetable",
      "Combine with rice and finish simply",
    ],
    steps: [
      { instruction: "Prepare the gourd and keep the pieces even.", cue: "Even cuts help the dish cook gently and uniformly.", caution: "" },
      { instruction: "Build the base over moderate heat without rushing it.", cue: "The pan should smell warm and mellow, not sharp or burnt.", caution: "" },
      { instruction: "Cook the gourd until it turns soft and gives off some moisture.", cue: "The texture should be tender, not watery and raw.", caution: "" },
      { instruction: "Add rice and finish simply so the dish stays calm and balanced.", cue: "The dish should feel gentle, not heavy or aggressively spiced.", caution: "" },
    ],
  },
};

function ok(data, requestId) {
  return { success: true, data, meta: { request_id: requestId, api_version: "v1" } };
}

function notFound(code, message, requestId) {
  return { success: false, error: { code, message, retryable: false }, meta: { request_id: requestId, api_version: "v1" } };
}

function issueMessage(issueType) {
  switch (issueType) {
    case "too_watery":
      return "Keep the pan uncovered for a few minutes and do not add more liquid yet.";
    case "too_dry":
      return "Lower the heat slightly and add a small splash of water before folding again.";
    case "burning":
      return "Move the pan off the heat immediately and reduce the flame before continuing.";
    case "bland":
      return "Taste for salt first, then think about acid or freshness.";
    default:
      return "Adjust gently and keep the heat under control.";
  }
}

async function initDb() {
  await pool.query(`
    create table if not exists user_preferences (
      user_id text primary key,
      primary_locale text not null,
      guidance_mode text not null,
      ambience_enabled boolean not null,
      ambience_mood text not null,
      updated_at timestamptz not null default now()
    );
  `);

  await pool.query(`
    create table if not exists cooking_sessions (
      session_id text primary key,
      recipe_id text not null,
      state text not null,
      current_phase text not null,
      current_step_number integer not null,
      guidance_mode text not null,
      session_locale text not null,
      ambience_enabled boolean not null,
      ambience_mood_tag text not null,
      audio_muted boolean not null,
      audio_ducking_active boolean not null,
      audio_requested_volume numeric not null,
      completed boolean not null,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );
  `);

  await pool.query(`
    create table if not exists session_issues (
      id bigserial primary key,
      session_id text not null,
      issue_type text not null,
      recovery_text text not null,
      created_at timestamptz not null default now()
    );
  `);

  await pool.query(`
    create table if not exists user_feedback (
      id bigserial primary key,
      category text not null,
      note text,
      session_id text,
      created_at timestamptz not null default now()
    );
  `);

  await pool.query(`
    insert into user_preferences (user_id, primary_locale, guidance_mode, ambience_enabled, ambience_mood)
    values ('local-user-1', 'en-KE', 'listen_only', true, 'calm_dining')
    on conflict (user_id) do nothing;
  `);
}

async function getPreferences() {
  const result = await pool.query(`select user_id, primary_locale, guidance_mode, ambience_enabled, ambience_mood from user_preferences where user_id = 'local-user-1' limit 1`);
  const row = result.rows[0];
  return {
    userId: row.user_id,
    primaryLocale: row.primary_locale,
    guidanceMode: row.guidance_mode,
    ambienceEnabled: row.ambience_enabled,
    ambienceMood: row.ambience_mood,
  };
}

async function savePreferences(updates) {
  const current = await getPreferences();
  const next = {
    userId: "local-user-1",
    primaryLocale: updates.primaryLocale ?? current.primaryLocale,
    guidanceMode: updates.guidanceMode ?? current.guidanceMode,
    ambienceEnabled: typeof updates.ambienceEnabled === "boolean" ? updates.ambienceEnabled : current.ambienceEnabled,
    ambienceMood: updates.ambienceMood ?? current.ambienceMood,
  };
  await pool.query(
    `update user_preferences set primary_locale = $1, guidance_mode = $2, ambience_enabled = $3, ambience_mood = $4, updated_at = now() where user_id = 'local-user-1'`,
    [next.primaryLocale, next.guidanceMode, next.ambienceEnabled, next.ambienceMood]
  );
  return next;
}

function mapSession(row) {
  return {
    sessionId: row.session_id,
    recipeId: row.recipe_id,
    recipeTitle: recipes[row.recipe_id]?.title ?? row.recipe_id,
    state: row.state,
    currentPhase: row.current_phase,
    currentStepNumber: row.current_step_number,
    guidanceMode: row.guidance_mode,
    sessionLocale: row.session_locale,
    ambienceEnabled: row.ambience_enabled,
    ambienceMoodTag: row.ambience_mood_tag,
    audioState: {
      muted: row.audio_muted,
      duckingActive: row.audio_ducking_active,
      requestedVolume: Number(row.audio_requested_volume),
    },
    completed: row.completed,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function createSession(recipeId, preferences) {
  const sessionId = crypto.randomUUID();
  await pool.query(
    `insert into cooking_sessions (
      session_id, recipe_id, state, current_phase, current_step_number,
      guidance_mode, session_locale, ambience_enabled, ambience_mood_tag,
      audio_muted, audio_ducking_active, audio_requested_volume, completed
    ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`,
    [
      sessionId,
      recipeId,
      "cook_active",
      "prep",
      1,
      preferences.guidanceMode,
      preferences.primaryLocale,
      preferences.ambienceEnabled,
      preferences.ambienceMood,
      false,
      true,
      0.35,
      false,
    ]
  );
  return getSession(sessionId);
}

async function getSession(sessionId) {
  const result = await pool.query(`select * from cooking_sessions where session_id = $1 limit 1`, [sessionId]);
  if (result.rowCount === 0) return null;
  return mapSession(result.rows[0]);
}

async function getLatestActiveSession() {
  const result = await pool.query(`select * from cooking_sessions where completed = false order by updated_at desc, created_at desc limit 1`);
  if (result.rowCount === 0) return null;
  return mapSession(result.rows[0]);
}

async function getSessionHistory(limit = 10) {
  const result = await pool.query(`select * from cooking_sessions order by updated_at desc, created_at desc limit $1`, [limit]);
  return result.rows.map(mapSession);
}

async function updateSessionAudio(sessionId, audioPatch) {
  const session = await getSession(sessionId);
  if (!session) return null;
  const nextAudio = { ...session.audioState, ...audioPatch };
  await pool.query(
    `update cooking_sessions set audio_muted = $1, audio_ducking_active = $2, audio_requested_volume = $3, updated_at = now() where session_id = $4`,
    [nextAudio.muted, nextAudio.duckingActive, nextAudio.requestedVolume, sessionId]
  );
  return nextAudio;
}

async function advanceSession(sessionId) {
  const session = await getSession(sessionId);
  if (!session) return null;
  const recipe = recipes[session.recipeId];
  const maxSteps = recipe.steps.length;
  let nextStep = session.currentStepNumber;
  let nextPhase = session.currentPhase;
  if (nextStep < maxSteps) {
    nextStep += 1;
    nextPhase = nextStep === maxSteps ? "finish" : "cook";
  }
  await pool.query(`update cooking_sessions set current_step_number = $1, current_phase = $2, updated_at = now() where session_id = $3`, [nextStep, nextPhase, sessionId]);
  return getSession(sessionId);
}

async function completeSession(sessionId) {
  await pool.query(`update cooking_sessions set state = 'completed', current_phase = 'serve', completed = true, updated_at = now() where session_id = $1`, [sessionId]);
  return getSession(sessionId);
}

async function recordIssue(sessionId, issueType, recoveryText) {
  await pool.query(`insert into session_issues (session_id, issue_type, recovery_text) values ($1,$2,$3)`, [sessionId, issueType, recoveryText]);
}

async function saveFeedback(category, note, sessionId = null) {
  const result = await pool.query(`insert into user_feedback (category, note, session_id) values ($1,$2,$3) returning id, category, note, session_id, created_at`, [category, note ?? "", sessionId]);
  return result.rows[0];
}

app.get("/health", async (_req, res) => {
  try {
    await pool.query("select 1");
    res.json({ ok: true, service: "nomad-beta-backend-v4", now: new Date().toISOString() });
  } catch {
    res.status(500).json({ ok: false, service: "nomad-beta-backend-v4", error: "database_unavailable" });
  }
});

app.get("/v1/me", async (_req, res) => {
  const prefs = await getPreferences();
  res.json(ok(prefs, "prefs-1"));
});

app.patch("/v1/me/preferences", async (req, res) => {
  const prefs = await savePreferences(req.body ?? {});
  res.json(ok(prefs, "prefs-2"));
});

app.post("/v1/generation/runs", (req, res) => {
  const prompt = req.body?.prompt_text || "your ingredients";
  const candidates = Object.values(recipes).map((item, index) => ({
    id: item.id,
    title: item.title,
    mode: item.mode,
    reason: index === 0 ? `A light, practical dish built from ${prompt}.` : item.reason,
    time: item.time,
    note: item.note,
    rankOrder: index + 1,
  }));
  res.status(201).json(ok({ run: { generationRunId: "db-run-4" }, candidates }, "gen-1"));
});

app.get("/v1/recipes/:id", (req, res) => {
  const recipe = recipes[req.params.id];
  if (!recipe) return res.status(404).json(notFound("RECIPE_NOT_FOUND", "Recipe not found", "recipe-1"));
  res.json(ok(recipe, "recipe-2"));
});

app.post("/v1/sessions", async (req, res) => {
  const recipeId = req.body?.recipe_id;
  if (!recipes[recipeId]) return res.status(404).json(notFound("RECIPE_NOT_FOUND", "Recipe not found", "session-1"));
  const prefs = await getPreferences();
  const session = await createSession(recipeId, prefs);
  res.status(201).json(ok(session, "session-2"));
});

app.get("/v1/sessions/latest", async (_req, res) => {
  const session = await getLatestActiveSession();
  if (!session) return res.status(404).json(notFound("SESSION_NOT_FOUND", "No active session", "session-latest-1"));
  res.json(ok(session, "session-latest-2"));
});

app.get("/v1/sessions/history", async (_req, res) => {
  const history = await getSessionHistory(10);
  res.json(ok(history, "session-history-1"));
});

app.get("/v1/sessions/:id", async (req, res) => {
  const session = await getSession(req.params.id);
  if (!session) return res.status(404).json(notFound("SESSION_NOT_FOUND", "Session not found", "session-3"));
  res.json(ok(session, "session-4"));
});

app.post("/v1/sessions/:id/issues", async (req, res) => {
  const session = await getSession(req.params.id);
  if (!session) return res.status(404).json(notFound("SESSION_NOT_FOUND", "Session not found", "issue-1"));
  const issueType = req.body?.issue_type || "unknown";
  const recoveryText = issueMessage(issueType);
  await recordIssue(req.params.id, issueType, recoveryText);
  res.status(201).json(ok({ issueType, recoveryText }, "issue-2"));
});

app.post("/v1/sessions/:id/audio-state", async (req, res) => {
  const audioState = await updateSessionAudio(req.params.id, req.body ?? {});
  if (!audioState) return res.status(404).json(notFound("SESSION_NOT_FOUND", "Session not found", "audio-1"));
  res.json(ok(audioState, "audio-2"));
});

app.post("/v1/sessions/:id/next-step", async (req, res) => {
  const session = await advanceSession(req.params.id);
  if (!session) return res.status(404).json(notFound("SESSION_NOT_FOUND", "Session not found", "step-1"));
  res.json(ok(session, "step-2"));
});

app.post("/v1/sessions/:id/complete", async (req, res) => {
  const session = await completeSession(req.params.id);
  if (!session) return res.status(404).json(notFound("SESSION_NOT_FOUND", "Session not found", "complete-1"));
  res.json(ok(session, "complete-2"));
});

app.post("/v1/feedback", async (req, res) => {
  const category = req.body?.category || "general";
  const note = req.body?.note || "";
  const sessionId = req.body?.sessionId || null;
  const feedback = await saveFeedback(category, note, sessionId);
  res.status(201).json(ok(feedback, "feedback-1"));
});

const PORT = process.env.PORT || 4000;

initDb()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`Nomad Beta backend v4 running on http://0.0.0.0:${PORT}`);
    });
  })
  .catch((error) => {
    console.error("Failed to initialize database:", error);
    process.exit(1);
  });
