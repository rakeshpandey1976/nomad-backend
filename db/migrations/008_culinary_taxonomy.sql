begin;

create extension if not exists pgcrypto;

create table if not exists regions (
    region_id uuid primary key default gen_random_uuid(),
    region_name text not null unique,
    description text,
    sort_order integer not null default 0,
    created_at timestamptz not null default now()
);

create table if not exists cuisines (
    cuisine_id uuid primary key default gen_random_uuid(),
    region_id uuid not null references regions(region_id) on delete restrict,
    cuisine_name text not null,
    country_code text,
    description text,
    status text not null default 'active',
    sort_order integer not null default 0,
    created_at timestamptz not null default now(),
    constraint cuisines_status_check
        check (status in ('active', 'draft', 'retired')),
    constraint uq_cuisines_region_name
        unique (region_id, cuisine_name)
);

create table if not exists subcuisines (
    subcuisine_id uuid primary key default gen_random_uuid(),
    cuisine_id uuid not null references cuisines(cuisine_id) on delete cascade,
    subcuisine_name text not null,
    description text,
    status text not null default 'active',
    created_at timestamptz not null default now(),
    constraint subcuisines_status_check
        check (status in ('active', 'draft', 'retired')),
    constraint uq_subcuisines_cuisine_name
        unique (cuisine_id, subcuisine_name)
);

create table if not exists dish_families (
    dish_family_id uuid primary key default gen_random_uuid(),
    family_name text not null unique,
    description text,
    parent_family_id uuid references dish_families(dish_family_id) on delete set null,
    created_at timestamptz not null default now()
);

create table if not exists techniques (
    technique_id uuid primary key default gen_random_uuid(),
    technique_name text not null unique,
    description text,
    difficulty_band text,
    status text not null default 'active',
    created_at timestamptz not null default now(),
    constraint techniques_status_check
        check (status in ('active', 'draft', 'retired'))
);

create index if not exists idx_cuisines_region_id on cuisines(region_id);
create index if not exists idx_cuisines_status on cuisines(status);
create index if not exists idx_subcuisines_cuisine_id on subcuisines(cuisine_id);
create index if not exists idx_dish_families_parent on dish_families(parent_family_id);
create index if not exists idx_techniques_status on techniques(status);

insert into regions (region_name, description, sort_order)
values
    ('South Asia', 'Culinary traditions across the South Asian region.', 10),
    ('East Africa', 'Culinary traditions across coastal and inland East Africa.', 20),
    ('Mediterranean', 'Culinary traditions around the Mediterranean basin.', 30),
    ('West Africa', 'Culinary traditions across West Africa.', 40),
    ('Middle East', 'Culinary traditions across the Middle East.', 50),
    ('Latin America', 'Culinary traditions across Latin America.', 60)
on conflict (region_name) do nothing;

insert into cuisines (region_id, cuisine_name, country_code, description, status, sort_order)
select r.region_id, v.cuisine_name, v.country_code, v.description, 'active', v.sort_order
from regions r
join (
    values
        ('South Asia', 'Indian', 'IN', 'Broad Indian culinary identity spanning multiple subcuisines.', 10),
        ('East Africa', 'Swahili', 'KE', 'Coastal East African cuisine with strong Indian Ocean influences.', 20),
        ('East Africa', 'Ethiopian', 'ET', 'Horn of Africa culinary tradition with stews, breads, and spice blends.', 30),
        ('Mediterranean', 'Italian', 'IT', 'Italian culinary tradition.', 40),
        ('Middle East', 'Levantine', null, 'Levantine culinary tradition.', 50),
        ('Latin America', 'Mexican', 'MX', 'Mexican culinary tradition.', 60)
) as v(region_name, cuisine_name, country_code, description, sort_order)
    on r.region_name = v.region_name
on conflict (region_id, cuisine_name) do nothing;

insert into subcuisines (cuisine_id, subcuisine_name, description, status)
select c.cuisine_id, v.subcuisine_name, v.description, 'active'
from cuisines c
join (
    values
        ('Indian', 'Gujarati', 'Western Indian subcuisine with strong vegetarian traditions.'),
        ('Indian', 'Tamil', 'South Indian Tamil culinary tradition.'),
        ('Swahili', 'Coastal Swahili', 'Coastal Swahili household and festive cooking.')
) as v(cuisine_name, subcuisine_name, description)
    on c.cuisine_name = v.cuisine_name
on conflict (cuisine_id, subcuisine_name) do nothing;

insert into dish_families (family_name, description)
values
    ('Rice Dishes', 'Dishes built around rice as the central structure.'),
    ('Porridges', 'Soft cooked grain-based dishes and porridges.'),
    ('Stews', 'Longer cooked liquid-based dishes with body and depth.'),
    ('Soups', 'Broth-forward or liquid-forward dishes.'),
    ('Flatbreads', 'Rolled or shaped pan- or oven-cooked breads.'),
    ('One-Pot Meals', 'Meals where most or all core components cook together in one vessel.'),
    ('Stir-Fries', 'Quick cooked dishes over higher heat with constant movement.'),
    ('Relishes', 'Condiments, accompaniments, and side preparations.')
on conflict (family_name) do nothing;

insert into techniques (technique_name, description, difficulty_band, status)
values
    ('Saute', 'Cook ingredients in a little fat over moderate to moderately high heat.', 'beginner', 'active'),
    ('Simmer', 'Cook gently in liquid just below a full boil.', 'beginner', 'active'),
    ('Tempering', 'Bloom whole or ground spices in hot fat to release aroma.', 'intermediate', 'active'),
    ('Steaming', 'Cook with moist heat from steam rather than direct immersion.', 'beginner', 'active'),
    ('Braising', 'Cook slowly with a combination of searing and moist heat.', 'intermediate', 'active')
on conflict (technique_name) do nothing;

commit;
