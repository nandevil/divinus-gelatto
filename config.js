// Configuração única do site e do painel.
// Supabase > Project Settings > API Keys: "Project URL" e a chave "Publishable" (sb_publishable_...).
// A chave publishable é pública por natureza: o banco só deixa o site ler o cardápio e criar pedidos.
// NUNCA coloque aqui a chave "secret" (sb_secret_...) nem a "service_role".
window.DIVINUS_CONFIG = {
  SUPABASE_URL: 'https://bwefsaqlkntahljpgkpi.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_Mp0gBB0ok_pOfEsKhXrW2Q_rYEBh8yy',
  // ID do Google Analytics 4 (ex.: G-ABC123XYZ). Vazio = sem Analytics.
  GA_ID: ''
};
