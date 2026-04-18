begin;

create extension if not exists pgcrypto;

create table if not exists recipes (
    recipe_id uuid primary key default gen_random_uuid(),
    slug text not null unique,
    canonical_title text not null,
    recipe_type text not null,
    cuisine_id uuid references cuisines(cuisine_id) on delete set null,
    subcuisine_id uuid references subcuisines(subcuisine_id) on delete set null,
    dish_family_id uuid not null references dish_families(dish_family_id) on delete restrict,
    difficulty_band text,
    estimated_time_minutes integer,
    default_servings integer,
    cultural_identity_note text,
    health_note text,
    status text not null default 'draft',
    is_public_beta boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint recipes_type_check
        check (recipe_type in ('traditional_anchor', 'adaptive_household', 'inventive_nomad')),
    constraint recipes_status_check
        check (status in ('draft', 'review', 'approved', 'retired'))
);

create table if not exists recipe_localizations (
    recipe_localization_id uuid primary key default gen_random_uuid(),
    recipe_id uuid not null references recipes(recipe_id) on delete cascade,
    locale_code text not null references locales(locale_code),
    localized_title text not null,
    summary_text text,
    cultural_note_localized text,
    health_note_localized text,
    created_at timestamptz not null default now(),
    constraint uq_recipe_localization unique (recipe_id, locale_code)
);

create table if not exists recipe_ingredients (
    recipe_ingredient_id uuid primary key default gen_random_uuid(),
    recipe_id uuid not null references recipes(recipe_id) on delete cascade,
    ingredient_id uuid not null references ingredients(ingredient_id) on delete restrict,
    is_optional boolean not null default false,
    is_garnish boolean not null default false,
    quantity_value numeric,
    quantity_unit text,
    quantity_text_override text,
    preparation_note text,
    sequence_order integer not null,
    constraint uq_recipe_ingredient_order unique (recipe_id, sequence_order)
);

create table if not exists recipe_phases (
    recipe_phase_id uuid primary key default gen_random_uuid(),
    recipe_id uuid not null references recipes(recipe_id) on delete cascade,
    phase_name text not null,
    display_title text not null,
    sequence_order integer not null,
    constraint uq_recipe_phase_order unique (recipe_id, sequence_order),
    constraint uq_recipe_phase_name unique (recipe_id, phase_name)
);

create table if not exists recipe_steps (
    recipe_step_id uuid primary key default gen_random_uuid(),
    recipe_id uuid not null references recipes(recipe_id) on delete cascade,
    recipe_phase_id uuid not null references recipe_phases(recipe_phase_id) on delete cascade,
    step_number integer not null,
    instruction_text text not null,
    spoken_instruction_text text,
    time_hint_minutes integer,
    sequence_order integer not null,
    constraint uq_recipe_step_number unique (recipe_id, step_number),
    constraint uq_recipe_step_order unique (recipe_id, sequence_order)
);

create table if not exists step_cues (
    step_cue_id uuid primary key default gen_random_uuid(),
    recipe_step_id uuid not null references recipe_steps(recipe_step_id) on delete cascade,
    cue_type text not null,
    cue_text text not null,
    is_primary boolean not null default false
);

create table if not exists step_cautions (
    step_caution_id uuid primary key default gen_random_uuid(),
    recipe_step_id uuid not null references recipe_steps(recipe_step_id) on delete cascade,
    caution_type text not null,
    caution_text text not null
);

create table if not exists step_recoveries (
    step_recovery_id uuid primary key default gen_random_uuid(),
    recipe_step_id uuid references recipe_steps(recipe_step_id) on delete cascade,
    issue_type text not null,
    recovery_text text not null,
    priority_rank integer not null default 0
);

create table if not exists recipe_techniques (
    recipe_technique_id uuid primary key default gen_random_uuid(),
    recipe_id uuid not null references recipes(recipe_id) on delete cascade,
    technique_id uuid not null references techniques(technique_id) on delete restrict,
    importance_band text,
    note_text text,
    constraint uq_recipe_technique unique (recipe_id, technique_id)
);

create table if not exists recipe_substitution_rules (
    recipe_substitution_rule_id uuid primary key default gen_random_uuid(),
    recipe_id uuid not null references recipes(recipe_id) on delete cascade,
    missing_ingredient_id uuid not null references ingredients(ingredient_id) on delete restrict,
    substitute_ingredient_id uuid not null references ingredients(ingredient_id) on delete restrict,
    rule_text text not null,
    quality_impact_note text
);

create table if not exists recipe_equipment_notes (
    recipe_equipment_note_id uuid primary key default gen_random_uuid(),
    recipe_id uuid not null references recipes(recipe_id) on delete cascade,
    equipment_name text not null,
    required_level text not null,
    adaptation_note text
);

create index if not exists idx_recipes_cuisine on recipes(cuisine_id);
create index if not exists idx_recipes_dish_family on recipes(dish_family_id);
create index if not exists idx_recipes_status on recipes(status);
create index if not exists idx_recipe_ingredients_recipe on recipe_ingredients(recipe_id);
create index if not exists idx_recipe_steps_recipe on recipe_steps(recipe_id);
create index if not exists idx_step_cues_step on step_cues(recipe_step_id);
create index if not exists idx_step_cautions_step on step_cautions(recipe_step_id);
create index if not exists idx_step_recoveries_step on step_recoveries(recipe_step_id);
create index if not exists idx_recipe_sub_rules_recipe on recipe_substitution_rules(recipe_id);
create index if not exists idx_recipe_equipment_recipe on recipe_equipment_notes(recipe_id);

insert into recipes (
    slug,
    canonical_title,
    recipe_type,
    cuisine_id,
    dish_family_id,
    difficulty_band,
    estimated_time_minutes,
    default_servings,
    cultural_identity_note,
    health_note,
    status,
    is_public_beta
)
select
    v.slug,
    v.canonical_title,
    v.recipe_type,
    c.cuisine_id,
    d.dish_family_id,
    v.difficulty_band,
    v.estimated_time_minutes,
    v.default_servings,
    v.cultural_identity_note,
    v.health_note,
    'approved',
    true
from (
    values
        ('pilaf', 'Bottle Gourd Rice Pilaf', 'adaptive_household', 'Indian', 'Rice Dishes', 'beginner', 30, 2, 'A practical household adaptation built around bottle gourd and rice.', 'Light and practical for everyday cooking.'),
        ('traditional', 'Lauki Chawal, Home-Style', 'traditional_anchor', 'Indian', 'Rice Dishes', 'beginner', 35, 2, 'A gentle home-style lauki chawal preparation rooted in everyday Indian cooking logic.', 'Simple household cooking with a lighter feel.')
) as v(slug, canonical_title, recipe_type, cuisine_name, dish_family_name, difficulty_band, estimated_time_minutes, default_servings, cultural_identity_note, health_note)
join cuisines c on c.cuisine_name = v.cuisine_name
join dish_families d on d.family_name = v.dish_family_name
on conflict (slug) do nothing;

insert into recipe_localizations (recipe_id, locale_code, localized_title, summary_text, cultural_note_localized, health_note_localized)
select r.recipe_id, v.locale_code, v.localized_title, v.summary_text, v.cultural_note_localized, v.health_note_localized
from recipes r
join (
    values
        ('pilaf', 'en-KE', 'Bottle Gourd Rice Pilaf', 'A light, practical bottle gourd and rice dish for everyday kitchens.', 'An adaptive household direction inspired by lauki chawal logic.', 'Light and practical for everyday cooking.'),
        ('traditional', 'en-KE', 'Lauki Chawal, Home-Style', 'A calmer home-style lauki chawal direction.', 'Closer to a traditional household preparation.', 'Gentle and balanced household cooking.'),
        ('traditional', 'hi-IN', 'लौकी चावल', 'घर की सादी लौकी चावल की तैयारी।', 'घरेलू शैली की पारंपरिक दिशा।', 'हल्का और संतुलित घरेलू भोजन।')
) as v(slug, locale_code, localized_title, summary_text, cultural_note_localized, health_note_localized)
    on r.slug = v.slug
on conflict (recipe_id, locale_code) do nothing;

insert into recipe_ingredients (
    recipe_id,
    ingredient_id,
    is_optional,
    is_garnish,
    quantity_value,
    quantity_unit,
    quantity_text_override,
    preparation_note,
    sequence_order
)
select r.recipe_id, i.ingredient_id, v.is_optional, v.is_garnish, v.quantity_value, v.quantity_unit, v.quantity_text_override, v.preparation_note, v.sequence_order
from recipes r
join (
    values
        ('pilaf', 'Bottle Gourd', false, false, 1, 'piece', null, 'Cut into small cubes.', 1),
        ('pilaf', 'Rice', false, false, 1, 'cup', null, 'Use washed rice.', 2),
        ('pilaf', 'Onion', false, false, 1, 'piece', null, 'Slice or chop finely.', 3),
        ('pilaf', 'Cumin Seed', false, false, 1, 'teaspoon', null, null, 4),
        ('pilaf', 'Oil', false, false, 1, 'tablespoon', null, null, 5),
        ('pilaf', 'Salt', false, false, null, null, 'to taste', null, 6),
        ('traditional', 'Bottle Gourd', false, false, 1, 'piece', null, 'Cut evenly.', 1),
        ('traditional', 'Rice', false, false, 1, 'cup', null, 'Use washed rice.', 2),
        ('traditional', 'Onion', true, false, 1, 'piece', null, 'Optional depending on household style.', 3),
        ('traditional', 'Cumin Seed', false, false, 1, 'teaspoon', null, null, 4),
        ('traditional', 'Oil', false, false, 1, 'tablespoon', null, null, 5),
        ('traditional', 'Salt', false, false, null, null, 'to taste', null, 6)
) as v(slug, ingredient_name, is_optional, is_garnish, quantity_value, quantity_unit, quantity_text_override, preparation_note, sequence_order)
    on r.slug = v.slug
join ingredients i on i.canonical_name = v.ingredient_name
on conflict (recipe_id, sequence_order) do nothing;

insert into recipe_phases (recipe_id, phase_name, display_title, sequence_order)
select r.recipe_id, v.phase_name, v.display_title, v.sequence_order
from recipes r
join (
    values
        ('pilaf', 'prep', 'Prep the ingredients evenly', 1),
        ('pilaf', 'base', 'Bloom cumin and soften onion', 2),
        ('pilaf', 'cook', 'Cook down the bottle gourd', 3),
        ('pilaf', 'finish', 'Fold in the rice gently and finish', 4),
        ('traditional', 'prep', 'Cut and prepare the gourd', 1),
        ('traditional', 'base', 'Cook the base gently', 2),
        ('traditional', 'cook', 'Add and soften the vegetable', 3),
        ('traditional', 'finish', 'Combine with rice and finish simply', 4)
) as v(slug, phase_name, display_title, sequence_order)
    on r.slug = v.slug
on conflict (recipe_id, sequence_order) do nothing;

insert into recipe_steps (
    recipe_id,
    recipe_phase_id,
    step_number,
    instruction_text,
    spoken_instruction_text,
    time_hint_minutes,
    sequence_order
)
select r.recipe_id, rp.recipe_phase_id, v.step_number, v.instruction_text, v.spoken_instruction_text, v.time_hint_minutes, v.sequence_order
from recipes r
join (
    values
        ('pilaf', 'prep', 1, 'Wash and cut the bottle gourd into small cubes.', 'Wash and cut the bottle gourd into small cubes.', 5, 1),
        ('pilaf', 'base', 2, 'Warm a little oil, add cumin, then soften the onion gently.', 'Warm a little oil, add cumin, then soften the onion gently.', 5, 2),
        ('pilaf', 'cook', 3, 'Add the bottle gourd and cook until the pan looks less watery.', 'Add the bottle gourd and cook until the pan looks less watery.', 10, 3),
        ('pilaf', 'finish', 4, 'Fold in the rice gently and finish with salt to taste.', 'Fold in the rice gently and finish with salt to taste.', 10, 4),
        ('traditional', 'prep', 1, 'Prepare the gourd and keep the pieces even.', 'Prepare the gourd and keep the pieces even.', 5, 1),
        ('traditional', 'base', 2, 'Build the base over moderate heat without rushing it.', 'Build the base over moderate heat without rushing it.', 5, 2),
        ('traditional', 'cook', 3, 'Cook the gourd until it turns soft and gives off some moisture.', 'Cook the gourd until it turns soft and gives off some moisture.', 10, 3),
        ('traditional', 'finish', 4, 'Add rice and finish simply so the dish stays calm and balanced.', 'Add rice and finish simply so the dish stays calm and balanced.', 10, 4)
) as v(slug, phase_name, step_number, instruction_text, spoken_instruction_text, time_hint_minutes, sequence_order)
    on r.slug = v.slug
join recipe_phases rp on rp.recipe_id = r.recipe_id and rp.phase_name = v.phase_name
on conflict (recipe_id, step_number) do nothing;

insert into step_cues (recipe_step_id, cue_type, cue_text, is_primary)
select rs.recipe_step_id, v.cue_type, v.cue_text, v.is_primary
from recipes r
join (
    values
        ('pilaf', 1, 'visual', 'Pieces should be small and fairly even.', true),
        ('pilaf', 2, 'smell', 'You want fragrance and softening, not deep browning.', true),
        ('pilaf', 3, 'visual', 'The vegetable should look softer and less wet.', true),
        ('pilaf', 4, 'texture', 'The rice should stay separate rather than mashed.', true),
        ('traditional', 1, 'visual', 'Even cuts help the dish cook gently and uniformly.', true),
        ('traditional', 2, 'smell', 'The pan should smell warm and mellow, not sharp or burnt.', true),
        ('traditional', 3, 'texture', 'The texture should be tender, not watery and raw.', true),
        ('traditional', 4, 'taste', 'The dish should feel gentle, not heavy or aggressively spiced.', true)
) as v(slug, step_number, cue_type, cue_text, is_primary)
    on r.slug = v.slug
join recipe_steps rs on rs.recipe_id = r.recipe_id and rs.step_number = v.step_number;

insert into step_cautions (recipe_step_id, caution_type, caution_text)
select rs.recipe_step_id, v.caution_type, v.caution_text
from recipes r
join (
    values
        ('pilaf', 2, 'burning', 'If the cumin darkens too fast, lower the heat.'),
        ('pilaf', 3, 'overwatering', 'Do not add extra water too early.')
) as v(slug, step_number, caution_type, caution_text)
    on r.slug = v.slug
join recipe_steps rs on rs.recipe_id = r.recipe_id and rs.step_number = v.step_number;

insert into step_recoveries (recipe_step_id, issue_type, recovery_text, priority_rank)
select rs.recipe_step_id, v.issue_type, v.recovery_text, v.priority_rank
from recipes r
join (
    values
        ('pilaf', 4, 'too_watery', 'Keep the pan uncovered for a few minutes and do not add more liquid yet.', 1),
        ('pilaf', 4, 'too_dry', 'Lower the heat slightly and add a small splash of water before folding again.', 2),
        ('pilaf', 4, 'burning', 'Move the pan off the heat immediately and reduce the flame before continuing.', 3),
        ('pilaf', 4, 'bland', 'Taste for salt first, then think about acid or freshness.', 4),
        ('traditional', 4, 'too_watery', 'Keep the pan uncovered briefly and let the excess moisture reduce gently.', 1),
        ('traditional', 4, 'bland', 'Taste for salt first and adjust gently rather than adding aggressive seasoning.', 2)
) as v(slug, step_number, issue_type, recovery_text, priority_rank)
    on r.slug = v.slug
join recipe_steps rs on rs.recipe_id = r.recipe_id and rs.step_number = v.step_number;

insert into recipe_techniques (recipe_id, technique_id, importance_band, note_text)
select r.recipe_id, t.technique_id, v.importance_band, v.note_text
from recipes r
join (
    values
        ('pilaf', 'Tempering', 'high', 'Blooming cumin is important for the base flavour.'),
        ('pilaf', 'Simmer', 'medium', 'Gentle cooking helps the bottle gourd release moisture properly.'),
        ('traditional', 'Tempering', 'medium', 'A modest bloom of spices supports the household-style base.'),
        ('traditional', 'Simmer', 'high', 'Gentle cooking defines the softer household texture.')
) as v(slug, technique_name, importance_band, note_text)
    on r.slug = v.slug
join techniques t on t.technique_name = v.technique_name
on conflict (recipe_id, technique_id) do nothing;

insert into recipe_substitution_rules (
    recipe_id,
    missing_ingredient_id,
    substitute_ingredient_id,
    rule_text,
    quality_impact_note
)
select r.recipe_id, i.ingredient_id, s.ingredient_id, v.rule_text, v.quality_impact_note
from recipes r
join (
    values
        ('pilaf', 'Bottle Gourd', 'Zucchini', 'Use zucchini if bottle gourd is unavailable in this household-style direction.', 'Texture and water release will differ slightly.'),
        ('traditional', 'Bottle Gourd', 'Zucchini', 'Zucchini can stand in when bottle gourd is unavailable, but the result will be less traditional.', 'The flavour identity becomes less anchored in lauki chawal logic.')
) as v(slug, missing_name, substitute_name, rule_text, quality_impact_note)
    on r.slug = v.slug
join ingredients i on i.canonical_name = v.missing_name
join ingredients s on s.canonical_name = v.substitute_name;

insert into recipe_equipment_notes (recipe_id, equipment_name, required_level, adaptation_note)
select r.recipe_id, v.equipment_name, v.required_level, v.adaptation_note
from recipes r
join (
    values
        ('pilaf', 'Saucepan or Pot', 'preferred', 'Use a covered pot that allows gentle finishing without crowding.'),
        ('traditional', 'Saucepan or Pot', 'preferred', 'A simple household pot is enough for this preparation.')
) as v(slug, equipment_name, required_level, adaptation_note)
    on r.slug = v.slug;

commit;
