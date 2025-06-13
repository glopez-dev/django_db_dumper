#!/bin/bash

# ===============================================
# DÉCOUVERTE AUTOMATIQUE DES TABLES DJANGO
# ===============================================

# Configuration (à adapter)
PROD_HOST="localhost"
PROD_PORT="5432"
PROD_DB="votre_db_prod"
PROD_USER="votre_user"
PROD_PASSWORD="votre_password"

export PGPASSWORD="$PROD_PASSWORD"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# ===============================================
# FONCTIONS DE DÉCOUVERTE
# ===============================================

discover_django_tables() {
    print_status "🔍 Découverte des tables Django..."
    
    # Tables de base Django
    local django_system_tables=$(psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
        "SELECT tablename FROM pg_tables 
         WHERE schemaname = 'public' 
         AND (tablename LIKE 'django_%' OR tablename LIKE 'auth_%')
         ORDER BY tablename;")
    
    # Tables d'applications (hors Django système)
    local app_tables=$(psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
        "SELECT tablename FROM pg_tables 
         WHERE schemaname = 'public' 
         AND tablename NOT LIKE 'django_%' 
         AND tablename NOT LIKE 'auth_%'
         AND tablename NOT LIKE 'pg_%'
         ORDER BY tablename;")
    
    echo ""
    echo "==================================="
    echo "   TABLES DJANGO SYSTÈME"
    echo "==================================="
    echo ""
    echo "# Tables de base Django à inclure généralement"
    echo "DJANGO_BASE_TABLES=("
    echo "$django_system_tables" | while read table; do
        if [ -n "$table" ]; then
            table=$(echo "$table" | sed 's/^ *//' | sed 's/ *$//')
            echo "    \"$table\""
        fi
    done
    echo ")"
    
    echo ""
    echo "==================================="
    echo "   TABLES D'APPLICATIONS"
    echo "==================================="
    echo ""
    echo "# Tables de vos applications Django"
    echo "YOUR_APP_TABLES=("
    echo "$app_tables" | while read table; do
        if [ ! -z "$table" ]; then
            table=$(echo "$table" | sed 's/^ *//' | sed 's/ *$//')
            echo "    \"$table\""
        fi
    done
    echo ")"
}

discover_sequences() {
    print_status "🔢 Découverte des séquences..."
    
    # Séquences Django système
    local django_sequences=$(psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
        "SELECT sequencename FROM pg_sequences 
         WHERE schemaname = 'public' 
         AND (sequencename LIKE 'django_%' OR sequencename LIKE 'auth_%')
         ORDER BY sequencename;")
    
    # Séquences d'applications
    local app_sequences=$(psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
        "SELECT sequencename FROM pg_sequences 
         WHERE schemaname = 'public' 
         AND sequencename NOT LIKE 'django_%' 
         AND sequencename NOT LIKE 'auth_%'
         ORDER BY sequencename;")
    
    echo ""
    echo "==================================="
    echo "   SÉQUENCES DJANGO SYSTÈME"
    echo "==================================="
    echo ""
    echo "# Séquences Django de base"
    echo "DJANGO_BASE_SEQUENCES=("
    echo "$django_sequences" | while read seq; do
        if [ ! -z "$seq" ]; then
            seq=$(echo "$seq" | sed 's/^ *//' | sed 's/ *$//')
            echo "    \"$seq\""
        fi
    done
    echo ")"
    
    echo ""
    echo "==================================="
    echo "   SÉQUENCES D'APPLICATIONS"
    echo "==================================="
    echo ""
    echo "# Séquences de vos applications"
    echo "YOUR_APP_SEQUENCES=("
    echo "$app_sequences" | while read seq; do
        if [ ! -z "$seq" ]; then
            seq=$(echo "$seq" | sed 's/^ *//' | sed 's/ *$//')
            echo "    \"$seq\""
        fi
    done
    echo ")"
}

analyze_table_sizes() {
    print_status "📊 Analyse des tailles de tables..."
    
    echo ""
    echo "==================================="
    echo "   ANALYSE DES TAILLES"
    echo "==================================="
    echo ""
    
    psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -c \
        "SELECT 
            tablename as \"Table\",
            n_tup_ins - n_tup_del as \"Lignes (est.)\",
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as \"Taille\"
         FROM pg_stat_user_tables 
         WHERE schemaname = 'public'
         ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"
    
    echo ""
    echo "# Tables avec beaucoup de données (> 10MB)"
    echo "LARGE_TABLES=("
    
    psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
        "SELECT tablename
         FROM pg_stat_user_tables 
         WHERE schemaname = 'public'
         AND pg_total_relation_size(schemaname||'.'||tablename) > 10485760
         ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;" | \
    while read table; do
        if [ ! -z "$table" ]; then
            table=$(echo "$table" | sed 's/^ *//' | sed 's/ *$//')
            echo "    \"$table\"  # Table volumineuse"
        fi
    done
    
    echo ")"
}

discover_foreign_keys() {
    print_status "🔗 Analyse des clés étrangères..."
    
    echo ""
    echo "==================================="
    echo "   CONTRAINTES DE CLÉS ÉTRANGÈRES"
    echo "==================================="
    echo ""
    echo "# Ordre de restauration suggéré (tables sans FK d'abord)"
    echo "SUGGESTED_ORDER=("
    
    # Tables sans contraintes FK sortantes
    psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
        "SELECT DISTINCT t.tablename
         FROM pg_tables t
         WHERE t.schemaname = 'public'
         AND t.tablename NOT IN (
             SELECT DISTINCT tc.table_name
             FROM information_schema.table_constraints tc
             WHERE tc.constraint_type = 'FOREIGN KEY'
             AND tc.table_schema = 'public'
         )
         ORDER BY t.tablename;" | \
    while read table; do
        if [ ! -z "$table" ]; then
            table=$(echo "$table" | sed 's/^ *//' | sed 's/ *$//')
            echo "    \"$table\"  # Pas de FK sortantes"
        fi
    done
    
    # Tables avec FK (à faire après)
    psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
        "SELECT DISTINCT tc.table_name
         FROM information_schema.table_constraints tc
         WHERE tc.constraint_type = 'FOREIGN KEY'
         AND tc.table_schema = 'public'
         ORDER BY tc.table_name;" | \
    while read table; do
        if [ ! -z "$table" ]; then
            table=$(echo "$table" | sed 's/^ *//' | sed 's/ *$//')
            echo "    \"$table\"  # A des FK"
        fi
    done
    
    echo ")"
    
    # Détail des FK
    echo ""
    echo "# Détail des contraintes FK:"
    psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -c \
        "SELECT 
            kcu.table_name as \"Table source\",
            kcu.column_name as \"Colonne\",
            ccu.table_name AS \"Table référencée\"
         FROM information_schema.table_constraints AS tc 
         JOIN information_schema.key_column_usage AS kcu
           ON tc.constraint_name = kcu.constraint_name
           AND tc.table_schema = kcu.table_schema
         JOIN information_schema.constraint_column_usage AS ccu
           ON ccu.constraint_name = tc.constraint_name
           AND ccu.table_schema = tc.table_schema
         WHERE tc.constraint_type = 'FOREIGN KEY' 
         AND tc.table_schema = 'public'
         ORDER BY kcu.table_name, kcu.column_name;"
}

detect_sensitive_data() {
    print_status "🔐 Détection de données sensibles..."
    
    echo ""
    echo "==================================="
    echo "   TABLES POTENTIELLEMENT SENSIBLES"
    echo "==================================="
    echo ""
    
    # Recherche de tables avec des colonnes sensibles
    local sensitive_patterns="password|email|phone|ssn|credit|card|token|secret|key|hash"
    
    echo "# Tables avec des colonnes potentiellement sensibles"
    echo "SENSITIVE_TABLES=("
    
    psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
        "SELECT DISTINCT table_name
         FROM information_schema.columns
         WHERE table_schema = 'public'
         AND (column_name ~* '$sensitive_patterns')
         ORDER BY table_name;" | \
    while read table; do
        if [ ! -z "$table" ]; then
            table=$(echo "$table" | sed 's/^ *//' | sed 's/ *$//')
            
            # Trouver les colonnes sensibles dans cette table
            local sensitive_cols=$(psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
                "SELECT string_agg(column_name, ', ')
                 FROM information_schema.columns
                 WHERE table_schema = 'public'
                 AND table_name = '$table'
                 AND (column_name ~* '$sensitive_patterns');" | sed 's/^ *//' | sed 's/ *$//')
            
            echo "    \"$table\"  # Colonnes: $sensitive_cols"
        fi
    done
    
    echo ")"
}

generate_config_file() {
    local output_file="discovered_config.sh"
    
    print_status "📝 Génération du fichier de configuration..."
    
    {
        echo "# ==============================================="
        echo "# CONFIGURATION GÉNÉRÉE AUTOMATIQUEMENT"
        echo "# Date: $(date)"
        echo "# Base source: $PROD_HOST:$PROD_PORT/$PROD_DB"
        echo "# ==============================================="
        echo ""
        echo "# PARAMÈTRES DE CONNEXION"
        echo "export PROD_HOST=\"$PROD_HOST\""
        echo "export PROD_PORT=\"$PROD_PORT\""
        echo "export PROD_DB=\"$PROD_DB\""
        echo "export PROD_USER=\"$PROD_USER\""
        echo "export PROD_PASSWORD=\"CHANGEZ_MOI\""
        echo ""
        echo "export DEV_CONTAINER=\"postgres_dev\""
        echo "export DEV_DB=\"${PROD_DB}_dev\""
        echo "export DEV_USER=\"postgres\""
        echo ""
    } > "$output_file"
    
    # Ajouter les découvertes
    discover_django_tables >> "$output_file"
    discover_sequences >> "$output_file"
    
    {
        echo ""
        echo "# Combiner toutes les tables"
        echo "TABLES_TO_MIGRATE=("
        echo "    \"\${DJANGO_BASE_TABLES[@]}\""
        echo "    \"\${YOUR_APP_TABLES[@]}\""
        echo ")"
        echo ""
        echo "# Combiner toutes les séquences"
        echo "SEQUENCES_TO_MIGRATE=("
        echo "    \"\${DJANGO_BASE_SEQUENCES[@]}\""
        echo "    \"\${YOUR_APP_SEQUENCES[@]}\""
        echo ")"
        echo ""
        echo "# Tables à vider avant insertion (à personnaliser)"
        echo "TABLES_TO_TRUNCATE=("
        echo "    \"django_session\""
        echo "    \"django_admin_log\""
        echo ")"
    } >> "$output_file"
    
    print_success "✅ Configuration générée dans: $output_file"
    print_warning "⚠️  N'oubliez pas de:"
    echo "   1. Modifier le mot de passe dans le fichier"
    echo "   2. Ajuster les noms de conteneur/base de dev"
    echo "   3. Personnaliser les listes selon vos besoins"
}

main_menu() {
    echo "🔍 DÉCOUVERTE AUTOMATIQUE DJANGO"
    echo "================================"
    echo ""
    echo "Base analysée: $PROD_HOST:$PROD_PORT/$PROD_DB"
    echo ""
    echo "1) 🔍 Découvrir toutes les tables Django"
    echo "2) 🔢 Découvrir les séquences"
    echo "3) 📊 Analyser les tailles de tables"
    echo "4) 🔗 Analyser les contraintes FK"
    echo "5) 🔐 Détecter les données sensibles"
    echo "6) 📝 Générer un fichier de configuration complet"
    echo "7) 🔄 Analyse complète (tout en une fois)"
    echo "8) ❌ Quitter"
    echo ""
}

main() {
    # Test de connexion
    if ! psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -c "SELECT 1;" > /dev/null 2>&1; then
        print_error "❌ Impossible de se connecter à la base de production"
        echo "Vérifiez vos paramètres de connexion en haut du script"
        exit 1
    fi
    
    while true; do
        main_menu
        read -p "Votre choix (1-8): " choice
        echo ""
        
        case $choice in
            1) discover_django_tables ;;
            2) discover_sequences ;;
            3) analyze_table_sizes ;;
            4) discover_foreign_keys ;;
            5) detect_sensitive_data ;;
            6) generate_config_file ;;
            7) 
                print_status "🚀 Analyse complète en cours..."
                discover_django_tables
                discover_sequences
                analyze_table_sizes
                discover_foreign_keys  
                detect_sensitive_data
                generate_config_file
                ;;
            8) 
                print_status "Au revoir!"
                exit 0
                ;;
            *) 
                print_error "Choix invalide"
                continue
                ;;
        esac
        
        echo ""
        read -p "Appuyez sur Entrée pour continuer..." 
    done
}

# Nettoyage
cleanup() {
    echo ""
    print_warning "Script interrompu"
    unset PGPASSWORD
    exit 1
}

trap cleanup INT TERM

# Exécution
main

# Nettoyage final
unset PGPASSWORD