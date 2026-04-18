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

const CURRENT_USER_ID = "local-user-1";

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

async function ensureBootstrapRows() {
  await pool.query(
    `insert into users (user_id, display_name, account_status, signup_source)
     values ($1, 'Nomad Beta User', 'active', 'beta_invite')
     on conflict (user_id) do nothing`,
    [CURRENT_USER_ID]
  );

  await pool.query(
    `insert into user_profiles (
      user_id, primary_locale_code, country_code, region_text,
      cooking_confidence_level, literacy_mode, guidance_mode
    ) values ($1, 'en-KE', 'KE', 'Mombasa', 'beginner', 'full_text', 'listen_only')
    on conflict (user_id) do nothing`,
    [CURRENT_USER_ID]
  );

  await pool.query(
    `insert into user_preferences (
      user_id, primary_locale, guidance_mode, ambience_enabled, ambience_mood,
      ambient_sound_default_level, voice_enabled, auto_resume_session, measurement_system, default_servings
    ) values ($1, 'en-KE', 'listen_only', true, 'calm_dining', 0.35, true, true, 'metric', 2)
    on conflict (user_id) do nothing`,
    [CURRENT_USER_ID]
  );
}

async function getMe() {
  const result = await pool.query(
    `select
        u.user_id,
        coalesce(up.primary_locale, p.primary_locale_code) as primary_locale,
        coalesce(up.guidance_mode, p.guidance_mode) as guidance_mode,
        coalesce(up.ambience_enabled, true) as ambience_enabled,
        coalesce(up.ambience_mood, 'calm_dining') as ambience_mood,
        coalesce(up.ambient_sound_default_level, 0.35) as ambient_sound_default_level,
        coalesce(up.voice_enabled, true) as voice_enabled,
        coalesce(up.auto_resume_session, true) as auto_resume_session,
        coalesce(up.measurement_system, 'metric') as measurement_system,
        up.default_servings
     from users u
     left join user_profiles p on p.user_id = u.user_id
     left join user_preferences up on up.user_id = u.user_id
     where u.user_id = $1
     limit 1`,
    [CURRENT_USER_ID]
  );

  const row = result.rows[0];
  return {
    userId: row.user_id,
    primaryLocale: row.primary_locale,
    guidanceMode: row.guidance_mode,
    ambienceEnabled: row.ambience_enabled,
    ambienceMood: row.ambience_mood,
  };
}

async function savePreferences(patch) {
  const current = await getMe();
  const nextPrimaryLocale = patch.primaryLocale ?? current.primaryLocale;
  const nextGuidanceMode = patch.guidanceMode ?? current.guidanceMode;
  const nextAmbienceEnabled = typeof patch.ambienceEnabled === 'boolean' ? patch.ambienceEnabled : current.ambienceEnabled;
  const nextAmbienceMood = patch.ambienceMood ?? current.ambienceMood;

  await pool.query(
    `update user_profiles
     set primary_locale_code = $1,
         guidance_mode = $2,
         updated_at = now()
     where user_id = $3`,
    [nextPrimaryLocale, nextGuidanceMode, CURRENT_USER_ID]
  );

  await pool.query(
    `update user_preferences
     set primary_locale = $1,
         guidance_mode = $2,
         ambience_enabled = $3,
         ambience_mood = $4,
         updated_at = now()
     where user_id = $5`,
    [nextPrimaryLocale, nextGuidanceMode, nextAmbienceEnabled, nextAmbienceMood, CURRENT_USER_ID]
  );

  return getMe();
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

async function createSession(recipeId) {
  const me = await getMe();
  const sessionId = crypto.randomUUID();

  await pool.query(
    `insert into cooking_sessions (
      session_id, user_id, recipe_id, state, current_phase, current_step_number,
      guidance_mode, session_locale, ambience_enabled, ambience_mood_tag,
      audio_muted, audio_ducking_active, audio_requested_volume, completed,
      started_at, last_active_at, created_at, updated_at
    ) values ($1,$2,$3,'active','prep',1,$4,$5,$6,$7,false,true,0.35,false,now(),now(),now(),now())`,
    [sessionId, CURRENT_USER_ID, recipeId, me.guidanceMode, me.primaryLocale, me.ambienceEnabled, me.ambienceMood]
  );

  await pool.query(
    `insert into session_audio_state (session_id, ambient_enabled, muted, ducking_active, current_track_ref, requested_volume)
     values ($1, $2, false, true, null, 0.35)
     on conflict (session_id) do nothing`,
    [sessionId, me.ambienceEnabled]
  );

  await pool.query(
    `insert into session_step_events (session_id, recipe_step_ref, event_type, event_payload_json)
     values ($1, null, 'step_started', '{}'::jsonb)`,
    [sessionId]
  );

  return getSession(sessionId);
}

async function getSession(sessionId) {
  const result = await pool.query(
    `select cs.*,
            coalesce(sa.ambient_enabled, true) as audio_ambient_enabled,
            coalesce(sa.muted, false) as audio_muted_effective,
            coalesce(sa.ducking_active, true) as audio_ducking_effective,
            coalesce(sa.requested_volume, 0.35) as audio_requested_effective
     from cooking_sessions cs
     left join session_audio_state sa on sa.session_id = cs.session_id
     where cs.session_id = $1
     limit 1`,
    [sessionId]
  );
  if (result.rowCount === 0) return null;
  const row = result.rows[0];
  return {
    sessionId: row.session_id,
    recipeId: row.recipe_id,
    recipeTitle: recipes[row.recipe_id]?.title ?? row.recipe_id,
    state: row.state,
    currentPhase: row.current_phase,
    currentStepNumber: row.current_step_number,
    guidanceMode: row.guidance_mode,
    sessionLocale: row.session_locale,
    ambienceEnabled: row.audio_ambient_enabled,
    ambienceMoodTag: row.ambience_mood_tag,
    audioState: {
      muted: row.audio_muted_effective,
      duckingActive: row.audio_ducking_effective,
      requestedVolume: Number(row.audio_requested_effective),
    },
    completed: row.state === 'completed',
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getLatestActiveSession() {
  const result = await pool.query(
    `select session_id
     from cooking_sessions
     where user_id = $1 and state <> 'completed'
     order by updated_at desc, created_at desc
     limit 1`,
    [CURRENT_USER_ID]
  );
  if (result.rowCount === 0) return null;
  return getSession(result.rows[0].session_id);
}

async function getSessionHistory(limit = 10) {
  const result = await pool.query(
    `select session_id
     from cooking_sessions
     where user_id = $1
     order by updated_at desc, created_at desc
     limit $2`,
    [CURRENT_USER_ID, limit]
  );
  const sessions = [];
  for (const row of result.rows) {
    const s = await getSession(row.session_id);
    if (s) sessions.push(s);
  }
  return sessions;
}

async function updateSessionAudio(sessionId, patch) {
  const existing = await getSession(sessionId);
  if (!existing) return null;
  const muted = typeof patch.muted === 'boolean' ? patch.muted : existing.audioState.muted;
  const duckingActive = typeof patch.duckingActive === 'boolean' ? patch.duckingActive : existing.audioState.duckingActive;
  const requestedVolume = typeof patch.requestedVolume === 'number' ? patch.requestedVolume : existing.audioState.requestedVolume;

  await pool.query(
    `insert into session_audio_state (session_id, ambient_enabled, muted, ducking_active, current_track_ref, requested_volume, last_changed_at)
     values ($1, $2, $3, $4, null, $5, now())
     on conflict (session_id)
     do update set ambient_enabled = excluded.ambient_enabled,
                   muted = excluded.muted,
                   ducking_active = excluded.ducking_active,
                   requested_volume = excluded.requested_volume,
                   last_changed_at = now()`,
    [sessionId, existing.ambienceEnabled, muted, duckingActive, requestedVolume]
  );

  await pool.query(
    `update cooking_sessions
     set updated_at = now(),
         last_active_at = now()
     where session_id = $1`,
    [sessionId]
  );

  return (await getSession(sessionId)).audioState;
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
    nextPhase = nextStep === maxSteps ? 'finish' : 'cook';
  }

  await pool.query(
    `update cooking_sessions
     set current_step_number = $1,
         current_phase = $2,
         updated_at = now(),
         last_active_at = now()
     where session_id = $3`,
    [nextStep, nextPhase, sessionId]
  );

  await pool.query(
    `insert into session_step_events (session_id, recipe_step_ref, event_type, event_payload_json)
     values ($1, null, 'step_completed', '{}'::jsonb)`,
    [sessionId]
  );

  return getSession(sessionId);
}

async function completeSession(sessionId) {
  await pool.query(
    `update cooking_sessions
     set state = 'completed',
         current_phase = 'serve',
         completed_at = now(),
         updated_at = now(),
         last_active_at = now()
     where session_id = $1`,
    [sessionId]
  );
  return getSession(sessionId);
}

async function recordIssue(sessionId, issueType, recoveryText) {
  await pool.query(
    `insert into session_issue_reports (
      session_issue_report_id, session_id, issue_type, user_note, recovery_text_served, step_number, created_at
    ) values (gen_random_uuid(), $1, $2, null, $3, null, now())`,
    [sessionId, issueType, recoveryText]
  );
}

async function saveFeedback(category, note, sessionId = null) {
  const result = await pool.query(
    `insert into user_feedback (
      feedback_id, user_id, session_id, feedback_category, feedback_text, device_context_json, created_at
    ) values (gen_random_uuid(), $1, $2, $3, $4, '{}'::jsonb, now())
     returning feedback_id, feedback_category, feedback_text, session_id, created_at`,
    [CURRENT_USER_ID, sessionId, category, note ?? '']
  );
  return result.rows[0];
}

app.get('/health', async (_req, res) => {
  try {
    await pool.query('select 1');
    res.json({ ok: true, service: 'nomad-db-build-pack-1b', now: new Date().toISOString() });
  } catch {
    res.status(500).json({ ok: false, service: 'nomad-db-build-pack-1b', error: 'database_unavailable' });
  }
});

app.get('/v1/me', async (_req, res) => {
  const me = await getMe();
  res.json(ok(me, 'me-1'));
});

app.patch('/v1/me/preferences', async (req, res) => {
  const prefs = await savePreferences(req.body ?? {});
  res.json(ok(prefs, 'prefs-1'));
});

app.post('/v1/generation/runs', (req, res) => {
  const prompt = req.body?.prompt_text || 'your ingredients';
  const candidates = Object.values(recipes).map((item, index) => ({
    id: item.id,
    title: item.title,
    mode: item.mode,
    reason: index === 0 ? `A light, practical dish built from ${prompt}.` : item.reason,
    time: item.time,
    note: item.note,
    rankOrder: index + 1,
  }));
  res.status(201).json(ok({ run: { generationRunId: crypto.randomUUID() }, candidates }, 'gen-1'));
});

app.get('/v1/recipes/:id', (req, res) => {
  const recipe = recipes[req.params.id];
  if (!recipe) return res.status(404).json(notFound('RECIPE_NOT_FOUND', 'Recipe not found', 'recipe-1'));
  res.json(ok(recipe, 'recipe-2'));
});

app.post('/v1/sessions', async (req, res) => {
  const recipeId = req.body?.recipe_id;
  if (!recipes[recipeId]) return res.status(404).json(notFound('RECIPE_NOT_FOUND', 'Recipe not found', 'session-1'));
  const session = await createSession(recipeId);
  res.status(201).json(ok(session, 'session-2'));
});

app.get('/v1/sessions/latest', async (_req, res) => {
  const session = await getLatestActiveSession();
  if (!session) return res.status(404).json(notFound('SESSION_NOT_FOUND', 'No active session', 'session-latest-1'));
  res.json(ok(session, 'session-latest-2'));
});

app.get('/v1/sessions/history', async (_req, res) => {
  const history = await getSessionHistory(10);
  res.json(ok(history, 'session-history-1'));
});

app.get('/v1/sessions/:id', async (req, res) => {
  const session = await getSession(req.params.id);
  if (!session) return res.status(404).json(notFound('SESSION_NOT_FOUND', 'Session not found', 'session-3'));
  res.json(ok(session, 'session-4'));
});

app.post('/v1/sessions/:id/issues', async (req, res) => {
  const session = await getSession(req.params.id);
  if (!session) return res.status(404).json(notFound('SESSION_NOT_FOUND', 'Session not found', 'issue-1'));
  const issueType = req.body?.issue_type || 'unknown';
  const recoveryText = issueMessage(issueType);
  await recordIssue(req.params.id, issueType, recoveryText);
  res.status(201).json(ok({ issueType, recoveryText }, 'issue-2'));
});

app.post('/v1/sessions/:id/audio-state', async (req, res) => {
  const audioState = await updateSessionAudio(req.params.id, req.body ?? {});
  if (!audioState) return res.status(404).json(notFound('SESSION_NOT_FOUND', 'Session not found', 'audio-1'));
  res.json(ok(audioState, 'audio-2'));
});

app.post('/v1/sessions/:id/next-step', async (req, res) => {
  const session = await advanceSession(req.params.id);
  if (!session) return res.status(404).json(notFound('SESSION_NOT_FOUND', 'Session not found', 'step-1'));
  res.json(ok(session, 'step-2'));
});

app.post('/v1/sessions/:id/complete', async (req, res) => {
  const session = await completeSession(req.params.id);
  if (!session) return res.status(404).json(notFound('SESSION_NOT_FOUND', 'Session not found', 'complete-1'));
  res.json(ok(session, 'complete-2'));
});

app.post('/v1/feedback', async (req, res) => {
  try {
    const category = req.body?.category || 'general';
    const note = req.body?.note || '';
    const sessionId = req.body?.sessionId || null;
    const feedback = await saveFeedback(category, note, sessionId);
    res.status(201).json(ok(feedback, 'feedback-1'));
  } catch (error) {
    console.error('Feedback route failed:', error);
    res.status(500).json({
      success: false,
      error: {
        code: 'FEEDBACK_SAVE_FAILED',
        message: 'Could not save feedback',
        retryable: false,
      },
      meta: {
        request_id: 'feedback-1',
        api_version: 'v1',
      },
    });
  }
});

ensureBootstrapRows()
  .then(() => {
    const PORT = process.env.PORT || 4000;
    app.listen(PORT, () => {
      console.log(`Nomad DB Build Pack 1A backend running on http://0.0.0.0:${PORT}`);
    });
  })
  .catch((error) => {
    console.error('Failed to initialize backend:', error);
    process.exit(1);
  });
