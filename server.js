import express from "express";
import cors from "cors";
import crypto from "crypto";

const app = express();
app.use(cors());
app.use(express.json());

let userPreferences = {
  userId: "local-user-1",
  primaryLocale: "en-KE",
  guidanceMode: "listen_only",
  ambienceEnabled: true,
  ambienceMood: "calm_dining",
};

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
      {
        instruction: "Wash and cut the bottle gourd into small cubes.",
        cue: "Pieces should be small and fairly even.",
        caution: "",
      },
      {
        instruction: "Warm a little oil, add cumin, then soften the onion gently.",
        cue: "You want fragrance and softening, not deep browning.",
        caution: "If the cumin darkens too fast, lower the heat.",
      },
      {
        instruction: "Add the bottle gourd and cook until the pan looks less watery.",
        cue: "The vegetable should look softer and less wet.",
        caution: "Do not add extra water too early.",
      },
      {
        instruction: "Fold in the rice gently and finish with salt to taste.",
        cue: "The rice should stay separate rather than mashed.",
        caution: "",
      },
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
      {
        instruction: "Prepare the gourd and keep the pieces even.",
        cue: "Even cuts help the dish cook gently and uniformly.",
        caution: "",
      },
      {
        instruction: "Build the base over moderate heat without rushing it.",
        cue: "The pan should smell warm and mellow, not sharp or burnt.",
        caution: "",
      },
      {
        instruction: "Cook the gourd until it turns soft and gives off some moisture.",
        cue: "The texture should be tender, not watery and raw.",
        caution: "",
      },
      {
        instruction: "Add rice and finish simply so the dish stays calm and balanced.",
        cue: "The dish should feel gentle, not heavy or aggressively spiced.",
        caution: "",
      },
    ],
  },
};

const sessions = new Map();

function ok(data, requestId) {
  return {
    success: true,
    data,
    meta: {
      request_id: requestId,
      api_version: "v1",
    },
  };
}

function notFound(code, message, requestId) {
  return {
    success: false,
    error: {
      code,
      message,
      retryable: false,
    },
    meta: {
      request_id: requestId,
      api_version: "v1",
    },
  };
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

app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "nomad-local-backend-v5", now: new Date().toISOString() });
});

app.get("/v1/me", (_req, res) => {
  res.json(ok(userPreferences, "prefs-1"));
});

app.patch("/v1/me/preferences", (req, res) => {
  userPreferences = {
    ...userPreferences,
    ...req.body,
  };
  res.json(ok(userPreferences, "prefs-2"));
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

  res.status(201).json(ok({ run: { generationRunId: "local-run-5" }, candidates }, "gen-1"));
});

app.get("/v1/recipes/:id", (req, res) => {
  const recipe = recipes[req.params.id];
  if (!recipe) {
    return res.status(404).json(notFound("RECIPE_NOT_FOUND", "Recipe not found", "recipe-1"));
  }
  res.json(ok(recipe, "recipe-2"));
});

app.post("/v1/sessions", (req, res) => {
  const sessionId = crypto.randomUUID();
  const recipeId = req.body?.recipe_id;
  const recipe = recipes[recipeId];

  if (!recipe) {
    return res.status(404).json(notFound("RECIPE_NOT_FOUND", "Recipe not found", "session-1"));
  }

  const session = {
    sessionId,
    recipeId,
    state: "cook_active",
    currentPhase: "prep",
    currentStepNumber: 1,
    guidanceMode: userPreferences.guidanceMode,
    sessionLocale: userPreferences.primaryLocale,
    ambienceEnabled: userPreferences.ambienceEnabled,
    ambienceMoodTag: userPreferences.ambienceMood,
    audioState: {
      muted: false,
      duckingActive: true,
      requestedVolume: 0.35,
    },
    completed: false,
    createdAt: new Date().toISOString(),
  };

  sessions.set(sessionId, session);
  res.status(201).json(ok(session, "session-2"));
});

app.get("/v1/sessions/:id", (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session) {
    return res.status(404).json(notFound("SESSION_NOT_FOUND", "Session not found", "session-3"));
  }
  res.json(ok(session, "session-4"));
});

app.post("/v1/sessions/:id/issues", (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session) {
    return res.status(404).json(notFound("SESSION_NOT_FOUND", "Session not found", "issue-1"));
  }

  const issueType = req.body?.issue_type || "unknown";
  const recoveryText = issueMessage(issueType);

  res.status(201).json(ok({ issueType, recoveryText }, "issue-2"));
});

app.post("/v1/sessions/:id/audio-state", (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session) {
    return res.status(404).json(notFound("SESSION_NOT_FOUND", "Session not found", "audio-1"));
  }

  session.audioState = {
    ...session.audioState,
    ...req.body,
  };

  sessions.set(req.params.id, session);
  res.json(ok(session.audioState, "audio-2"));
});

app.post("/v1/sessions/:id/next-step", (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session) {
    return res.status(404).json(notFound("SESSION_NOT_FOUND", "Session not found", "step-1"));
  }

  const recipe = recipes[session.recipeId];
  const maxSteps = recipe.steps.length;

  if (session.currentStepNumber < maxSteps) {
    session.currentStepNumber += 1;
    session.currentPhase = session.currentStepNumber === maxSteps ? "finish" : "cook";
  }

  sessions.set(req.params.id, session);
  res.json(ok(session, "step-2"));
});

app.post("/v1/sessions/:id/complete", (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session) {
    return res.status(404).json(notFound("SESSION_NOT_FOUND", "Session not found", "complete-1"));
  }

  session.state = "completed";
  session.currentPhase = "serve";
  session.completed = true;

  sessions.set(req.params.id, session);
  res.json(ok(session, "complete-2"));
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => {
  console.log(`Nomad local backend v5 running on http://0.0.0.0:${PORT}`);
});