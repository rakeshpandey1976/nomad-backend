begin;

create extension if not exists pgcrypto;

create table if not exists ingredients (
    ingredient_id uuid primary key default gen_random_uuid(),
    canonical_name text not null unique,
    ingredient_type text not null,
    parent_ingredient_id uuid references ingredients(ingredient_id) on delete set null,
    default_unit_family text,
    is_core boolean not null default false,
    status text not null default 'active',
    created_at timestamptz not null default now(),
    constraint ingredients_status_check
        check (status in ('active', 'draft', 'retired'))
);

create table if not exists ingredient_local_names (
    ingredient_local_name_id uuid primary key default gen_random_uuid(),
    ingredient_id uuid not null references ingredients(ingredient_id) on delete cascade,
    locale_code text not null references locales(locale_code),
    display_name text not null,
    alternate_name text,
    is_primary boolean not null default false,
    created_at timestamptz not null default now(),
    constraint uq_ingredient_local_name
        unique (ingredient_id, locale_code, display_name)
);

create table if not exists ingredient_variants (
    ingredient_variant_id uuid primary key default gen_random_uuid(),
    ingredient_id uuid not null references ingredients(ingredient_id) on delete cascade,
    variant_name text not null,
    region_id uuid references regions(region_id) on delete set null,
    notes text,
    created_at timestamptz not null default now(),
    constraint uq_ingredient_variant
        unique (ingredient_id, variant_name)
);

create table if not exists ingredient_behaviours (
    ingredient_behaviour_id uuid primary key default gen_random_uuid(),
    ingredient_id uuid not null references ingredients(ingredient_id) on delete cascade,
    behaviour_type text not null,
    severity_band text,
    note_text text,
    created_at timestamptz not null default now()
);

create table if not exists ingredient_substitutions (
    substitution_id uuid primary key default gen_random_uuid(),
    ingredient_id uuid not null references ingredients(ingredient_id) on delete cascade,
    substitute_ingredient_id uuid not null references ingredients(ingredient_id) on delete cascade,
    substitution_type text not null,
    context_note text,
    cuisine_id uuid references cuisines(cuisine_id) on delete set null,
    dish_family_id uuid references dish_families(dish_family_id) on delete set null,
    created_at timestamptz not null default now(),
    constraint uq_ingredient_substitution
        unique (ingredient_id, substitute_ingredient_id, substitution_type)
);

create table if not exists ingredient_nutrition_refs (
    ingredient_nutrition_ref_id uuid primary key default gen_random_uuid(),
    ingredient_id uuid not null references ingredients(ingredient_id) on delete cascade,
    source_system text not null,
    source_record_id text not null,
    reference_note text,
    updated_at timestamptz not null default now(),
    constraint uq_ingredient_nutrition_ref
        unique (ingredient_id, source_system, source_record_id)
);

create index if not exists idx_ingredients_type on ingredients(ingredient_type);
create index if not exists idx_ingredients_status on ingredients(status);
create index if not exists idx_ingredient_local_names_ingredient on ingredient_local_names(ingredient_id);
create index if not exists idx_ingredient_variants_ingredient on ingredient_variants(ingredient_id);
create index if not exists idx_ingredient_behaviours_ingredient on ingredient_behaviours(ingredient_id);
create index if not exists idx_ingredient_substitutions_ingredient on ingredient_substitutions(ingredient_id);
create index if not exists idx_ingredient_substitutions_substitute on ingredient_substitutions(substitute_ingredient_id);
create index if not exists idx_ingredient_nutrition_refs_ingredient on ingredient_nutrition_refs(ingredient_id);

insert into ingredients (canonical_name, ingredient_type, default_unit_family, is_core, status)
values
    ('Bottle Gourd', 'vegetable', 'piece', true, 'active'),
    ('Rice', 'grain', 'weight', true, 'active'),
    ('Onion', 'vegetable', 'piece', true, 'active'),
    ('Cumin Seed', 'spice', 'weight', true, 'active'),
    ('Oil', 'oil', 'volume', true, 'active'),
    ('Salt', 'condiment', 'weight', true, 'active'),
    ('Tomato', 'vegetable', 'piece', true, 'active'),
    ('Zucchini', 'vegetable', 'piece', false, 'active')
on conflict (canonical_name) do nothing;

insert into ingredient_local_names (ingredient_id, locale_code, display_name, alternate_name, is_primary)
select i.ingredient_id, v.locale_code, v.display_name, v.alternate_name, v.is_primary
from ingredients i
join (
    values
        ('Bottle Gourd', 'en-KE', 'Bottle Gourd', null, true),
        ('Bottle Gourd', 'hi-IN', 'Lauki', 'Doodhi', true),
        ('Rice', 'en-KE', 'Rice', null, true),
        ('Onion', 'en-KE', 'Onion', null, true),
        ('Cumin Seed', 'en-KE', 'Cumin Seed', 'Jeera', true),
        ('Cumin Seed', 'hi-IN', 'Jeera', 'Cumin Seed', true),
        ('Oil', 'en-KE', 'Oil', null, true),
        ('Salt', 'en-KE', 'Salt', null, true),
        ('Tomato', 'en-KE', 'Tomato', null, true),
        ('Zucchini', 'en-KE', 'Zucchini', null, true)
) as v(canonical_name, locale_code, display_name, alternate_name, is_primary)
    on i.canonical_name = v.canonical_name
on conflict (ingredient_id, locale_code, display_name) do nothing;

insert into ingredient_variants (ingredient_id, variant_name, region_id, notes)
select i.ingredient_id, v.variant_name, r.region_id, v.notes
from ingredients i
join (
    values
        ('Rice', 'Long-Grain Rice', 'South Asia', 'Common long-grain rice used in many household rice dishes.'),
        ('Onion', 'Red Onion', 'East Africa', 'Common onion variant in East African cooking.'),
        ('Oil', 'Sunflower Oil', 'East Africa', 'Common neutral cooking oil.')
) as v(canonical_name, variant_name, region_name, notes)
    on i.canonical_name = v.canonical_name
left join regions r on r.region_name = v.region_name
on conflict (ingredient_id, variant_name) do nothing;

insert into ingredient_behaviours (ingredient_id, behaviour_type, severity_band, note_text)
select i.ingredient_id, v.behaviour_type, v.severity_band, v.note_text
from ingredients i
join (
    values
        ('Bottle Gourd', 'releases_water', 'medium', 'Bottle gourd releases moisture as it cooks.'),
        ('Rice', 'absorbs_water', 'high', 'Rice absorbs liquid and can turn mushy if overhydrated.'),
        ('Onion', 'softens_quickly', 'medium', 'Onion softens early and helps form the base.'),
        ('Cumin Seed', 'splutters_in_hot_oil', 'medium', 'Cumin blooms quickly in hot oil and can burn if rushed.')
) as v(canonical_name, behaviour_type, severity_band, note_text)
    on i.canonical_name = v.canonical_name;

insert into ingredient_substitutions (
    ingredient_id,
    substitute_ingredient_id,
    substitution_type,
    context_note,
    cuisine_id,
    dish_family_id
)
select
    i.ingredient_id,
    s.ingredient_id,
    v.substitution_type,
    v.context_note,
    c.cuisine_id,
    d.dish_family_id
from (
    values
        ('Bottle Gourd', 'Zucchini', 'acceptable', 'Works when bottle gourd is unavailable in simple household rice or stew applications.', 'Indian', 'Rice Dishes'),
        ('Rice', 'Long-Grain Rice', 'close', 'A long-grain variant is usually a close substitution for general rice cooking.', null, 'Rice Dishes')
) as v(from_name, to_name, substitution_type, context_note, cuisine_name, dish_family_name)
join ingredients i on i.canonical_name = v.from_name
join ingredients s on s.canonical_name = v.to_name
left join cuisines c on c.cuisine_name = v.cuisine_name
left join dish_families d on d.family_name = v.dish_family_name
on conflict (ingredient_id, substitute_ingredient_id, substitution_type) do nothing;

insert into ingredient_nutrition_refs (ingredient_id, source_system, source_record_id, reference_note)
select i.ingredient_id, v.source_system, v.source_record_id, v.reference_note
from ingredients i
join (
    values
        ('Bottle Gourd', 'manual', 'bottle-gourd-manual-ref', 'Placeholder reference until external nutrition mapping is added.'),
        ('Rice', 'manual', 'rice-manual-ref', 'Placeholder reference until external nutrition mapping is added.'),
        ('Onion', 'manual', 'onion-manual-ref', 'Placeholder reference until external nutrition mapping is added.')
) as v(canonical_name, source_system, source_record_id, reference_note)
    on i.canonical_name = v.canonical_name
on conflict (ingredient_id, source_system, source_record_id) do nothing;

commit;
