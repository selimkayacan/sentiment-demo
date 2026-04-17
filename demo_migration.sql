-- ═══════════════════════════════════════════════════════════════
-- DEMO PLATFORMU MİGRASYONU
-- ═══════════════════════════════════════════════════════════════

-- 1. Demo kullanıcılar tablosu
CREATE TABLE IF NOT EXISTS demo_users (
    user_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT UNIQUE NOT NULL,
    company_name  TEXT NOT NULL,
    is_confirmed  BOOLEAN DEFAULT false,
    is_blocked    BOOLEAN DEFAULT false,
    confirmed_at  TIMESTAMPTZ,
    expires_at    TIMESTAMPTZ,
    customer_id   UUID REFERENCES customers(customer_id) ON DELETE SET NULL,
    brand_id      UUID REFERENCES brands(brand_id) ON DELETE SET NULL,
    brand_name    TEXT,
    sources       JSONB DEFAULT '[]',
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Demo token tablosu (konfirmasyon linkleri)
CREATE TABLE IF NOT EXISTS demo_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID REFERENCES demo_users(user_id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL,
    token_type  TEXT DEFAULT 'confirmation',
    expires_at  TIMESTAMPTZ NOT NULL,
    used        BOOLEAN DEFAULT false,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Brands tablosuna demo_user_id ekle
ALTER TABLE brands ADD COLUMN IF NOT EXISTS demo_user_id UUID REFERENCES demo_users(user_id) ON DELETE SET NULL;

-- 4. İndeksler
CREATE INDEX IF NOT EXISTS idx_demo_users_email ON demo_users(email);
CREATE INDEX IF NOT EXISTS idx_demo_tokens_user ON demo_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_brands_demo_user ON brands(demo_user_id);

-- 5. RLS — demo_users
ALTER TABLE demo_users ENABLE ROW LEVEL SECURITY;

-- Admin her şeyi görebilir
CREATE POLICY demo_users_admin ON demo_users
    FOR ALL TO authenticated
    USING (auth_is_admin());

-- Kullanıcı sadece kendi kaydını görebilir (demo flow'da anon ile çalışıyoruz)
-- Demo endpoint'leri service key ile çalıştığı için RLS burada daha az kritik
-- Ama anon key client'a verilmeyeceği için ek kısıt koymuyoruz

-- 6. RLS — brands (demo kullanıcıları sadece kendi markasını görsün)
-- Mevcut RLS varsa drop et, yeniden oluştur
DROP POLICY IF EXISTS brands_isolation ON brands;
CREATE POLICY brands_isolation ON brands
    FOR ALL TO authenticated
    USING (
        auth_is_admin()
        OR customer_id IN (
            SELECT customer_id FROM users WHERE user_id = auth.uid()
        )
    );

-- 7. RLS — locations
ALTER TABLE locations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS locations_isolation ON locations;
CREATE POLICY locations_isolation ON locations
    FOR ALL TO authenticated
    USING (
        auth_is_admin()
        OR brand_id IN (
            SELECT b.brand_id FROM brands b
            JOIN users u ON u.customer_id = b.customer_id
            WHERE u.user_id = auth.uid()
        )
    );

-- 8. RLS — reviews
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS reviews_isolation ON reviews;
CREATE POLICY reviews_isolation ON reviews
    FOR ALL TO authenticated
    USING (
        auth_is_admin()
        OR location_id IN (
            SELECT l.location_id FROM locations l
            JOIN brands b ON b.brand_id = l.brand_id
            JOIN users u ON u.customer_id = b.customer_id
            WHERE u.user_id = auth.uid()
        )
    );

-- 9. RLS — review_analysis
ALTER TABLE review_analysis ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS review_analysis_isolation ON review_analysis;
CREATE POLICY review_analysis_isolation ON review_analysis
    FOR ALL TO authenticated
    USING (
        auth_is_admin()
        OR review_id IN (
            SELECT r.review_id FROM reviews r
            JOIN locations l ON l.location_id = r.location_id
            JOIN brands b ON b.brand_id = l.brand_id
            JOIN users u ON u.customer_id = b.customer_id
            WHERE u.user_id = auth.uid()
        )
    );

-- 10. system_settings tablosundaki app_secret'ı koru
-- Demo kullanıcıları bu tabloyu okuyamaz
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS system_settings_admin_only ON system_settings;
CREATE POLICY system_settings_admin_only ON system_settings
    FOR ALL TO authenticated
    USING (auth_is_admin());

-- Servis URL'leri için ayrı tablo — sadece gmaps_url içerecek, secret değil
CREATE TABLE IF NOT EXISTS public_settings (
    key   TEXT PRIMARY KEY,
    value TEXT
);

ALTER TABLE public_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_settings_read ON public_settings
    FOR SELECT TO authenticated, anon
    USING (true);  -- herkes okuyabilir ama sadece gmaps_url gibi güvenli bilgiler

-- gmaps_url public_settings'e taşı (eğer system_settings'teyse)
INSERT INTO public_settings (key, value)
SELECT key, value FROM system_settings WHERE key = 'gmaps_url'
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

COMMENT ON TABLE demo_users IS 'Demo platformu kayıtları — LinkedIn kampanyası';
COMMENT ON TABLE demo_tokens IS 'Mail konfirmasyon tokenleri';
