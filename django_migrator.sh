#!/bin/bash

# ===============================================
# MIGRATEUR DE DONNÉES DJANGO - VERSION MODULAIRE
# ===============================================

# Charger la configuration
CONFIG_FILE="migration_config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Fichier de configuration '$CONFIG_FILE' non trouvé"
    echo ""
    echo "💡 Créez le fichier migration_config.sh avec vos paramètres"
    echo "   Exemple disponible dans les artifacts Claude"
    exit 1
fi

source "$CONFIG_FILE"

# ===============================================
# SCRIPT PRINCIPAL
# ===============================================

DUMP_DIR="./dumps/django_data_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DUMP_DIR"

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

export PGPASSWORD="$PROD_PASSWORD"

# ===============================================
# FONCTIONS PRINCIPALES
# ===============================================

dump_data() {
    print_status "🚀 Début de l'export des données Django..."
    
    local successful_tables=0
    local total_rows=0
    
    # Export des tables
    for table in "${TABLES_TO_MIGRATE[@]}"; do
        if [ -z "$table" ]; then continue; fi
        
        print_status "📦 Export de $table..."
        
        # Vérifier l'existence
        local exists=$(psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
            "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = '$table');" | tr -d ' ')
        
        if [ "$exists" = "f" ]; then
            print_warning "Table $table n'existe pas dans la production"
            continue
        fi
        
        # Export
        pg_dump -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" \
            --data-only \
            --no-owner \
            --no-privileges \
            --disable-triggers \
            --table="$table" \
            -f "$DUMP_DIR/table_${table}.sql"
        
        if [ $? -eq 0 ]; then
            local rows=$(grep -c "INSERT INTO" "$DUMP_DIR/table_${table}.sql" 2>/dev/null || echo "0")
            print_success "✅ $table ($rows lignes)"
            ((successful_tables++))
            ((total_rows += rows))
        else
            print_error "❌ Erreur export $table"
        fi
    done
    
    # Export des séquences
    print_status "🔢 Export des séquences..."
    {
        echo "-- Séquences Django $(date)"
        echo "-- Remise à niveau avec les valeurs de production"
        echo ""
    } > "$DUMP_DIR/sequences.sql"
    
    local successful_sequences=0
    for seq in "${SEQUENCES_TO_MIGRATE[@]}"; do
        if [ -z "$seq" ]; then continue; fi
        
        local value=$(psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
            "SELECT last_value FROM $seq;" 2>/dev/null | tr -d ' ')
        
        if [ ! -z "$value" ] && [ "$value" != "" ]; then
            echo "SELECT setval('$seq', $value, true);" >> "$DUMP_DIR/sequences.sql"
            print_success "✅ $seq (valeur: $value)"
            ((successful_sequences++))
        else
            print_warning "⚠️  Séquence $seq introuvable"
        fi
    done
    
    print_success "🎉 Export terminé: $successful_tables tables, $successful_sequences séquences, $total_rows lignes"
}

restore_data() {
    print_status "🔄 Restauration dans le conteneur Docker..."
    
    # Vérifier le conteneur
    if ! docker ps --format "{{.Names}}" | grep -q "^$DEV_CONTAINER$"; then
        print_error "Conteneur '$DEV_CONTAINER' introuvable"
        return 1
    fi
    
    # Copier les données
    print_status "📋 Copie des fichiers..."
    docker cp "$DUMP_DIR" "$DEV_CONTAINER:/tmp/django_restore"
    
    # Script de restauration dans le conteneur
    cat > "$DUMP_DIR/restore_in_container.sql" << EOF
-- Script de restauration Django
BEGIN;

-- Désactiver les contraintes temporairement
SET session_replication_role = replica;

-- Vider les tables spécifiées
EOF
    
    for table in "${TABLES_TO_TRUNCATE[@]}"; do
        if [ ! -z "$table" ]; then
            echo "TRUNCATE TABLE $table CASCADE;" >> "$DUMP_DIR/restore_in_container.sql"
        fi
    done
    
    echo "COMMIT;" >> "$DUMP_DIR/restore_in_container.sql"
    
    # Copier le script de restauration
    docker cp "$DUMP_DIR/restore_in_container.sql" "$DEV_CONTAINER:/tmp/"
    
    # Exécuter le script de préparation
    print_status "🧹 Préparation de la base..."
    docker exec "$DEV_CONTAINER" psql -U "$DEV_USER" -d "$DEV_DB" -f "/tmp/restore_in_container.sql"
    
    # Restaurer les données
    local restored_tables=0
    
    # Utiliser l'ordre de restauration si défini, sinon ordre par défaut
    local tables_order=("${RESTORATION_ORDER[@]}")
    if [ ${#tables_order[@]} -eq 0 ]; then
        tables_order=("${TABLES_TO_MIGRATE[@]}")
    fi
    
    for table in "${tables_order[@]}"; do
        if [ -f "$DUMP_DIR/table_${table}.sql" ]; then
            print_status "📦 Restauration de $table..."
            
            docker exec "$DEV_CONTAINER" psql -U "$DEV_USER" -d "$DEV_DB" \
                -f "/tmp/django_restore/$(basename $DUMP_DIR)/table_${table}.sql"
            
            if [ $? -eq 0 ]; then
                print_success "✅ $table restaurée"
                ((restored_tables++))
            else
                print_error "❌ Erreur restauration $table"
            fi
        fi
    done
    
    # Restaurer les séquences
    if [ -f "$DUMP_DIR/sequences.sql" ]; then
        print_status "🔢 Restauration des séquences..."
        docker exec "$DEV_CONTAINER" psql -U "$DEV_USER" -d "$DEV_DB" \
            -f "/tmp/django_restore/$(basename $DUMP_DIR)/sequences.sql"
        
        if [ $? -eq 0 ]; then
            print_success "✅ Séquences restaurées"
        fi
    fi
    
    # Réactiver les contraintes
    print_status "🔒 Réactivation des contraintes..."
    docker exec "$DEV_CONTAINER" psql -U "$DEV_USER" -d "$DEV_DB" -c \
        "SET session_replication_role = DEFAULT;"
    
    # Nettoyer
    docker exec "$DEV_CONTAINER" rm -rf "/tmp/django_restore" "/tmp/restore_in_container.sql"
    
    print_success "🎉 Restauration terminée: $restored_tables tables"
}

show_stats() {
    print_status "📊 Statistiques des tables à migrer..."
    
    {
        echo "RAPPORT DE MIGRATION DJANGO"
        echo "=========================="
        echo "Date: $(date)"
        echo "Base source: $PROD_HOST:$PROD_PORT/$PROD_DB"
        echo "Base cible: $DEV_CONTAINER/$DEV_DB"
        echo ""
        printf "%-40s %-15s %-15s\n" "TABLE" "LIGNES" "TAILLE"
        echo "------------------------------------------------------------------------"
        
        local total_rows=0
        local total_size=0
        
        for table in "${TABLES_TO_MIGRATE[@]}"; do
            if [ -z "$table" ]; then continue; fi
            
            local stats=$(psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
                "SELECT 
                    COALESCE(n_tup_ins - n_tup_del, 0),
                    pg_total_relation_size('$table')
                 FROM pg_stat_user_tables 
                 WHERE tablename = '$table';" 2>/dev/null)
            
            if [ ! -z "$stats" ]; then
                local rows=$(echo "$stats" | awk '{print $1}' | tr -d ' ')
                local size_bytes=$(echo "$stats" | awk '{print $2}' | tr -d ' ')
                local size_human=$(psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
                    "SELECT pg_size_pretty($size_bytes);" 2>/dev/null | tr -d ' ')
                
                printf "%-40s %-15s %-15s\n" "$table" "$rows" "$size_human"
                ((total_rows += rows))
                ((total_size += size_bytes))
            else
                printf "%-40s %-15s %-15s\n" "$table" "N/A" "N/A"
            fi
        done
        
        echo "------------------------------------------------------------------------"
        local total_size_human=$(psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
            "SELECT pg_size_pretty($total_size);" 2>/dev/null | tr -d ' ')
        printf "%-40s %-15s %-15s\n" "TOTAL" "$total_rows" "$total_size_human"
        
    } | tee "$DUMP_DIR/migration_report.txt"
}

check_sensitive_tables() {
    if [ ${#SENSITIVE_TABLES[@]} -gt 0 ]; then
        print_warning "⚠️  Tables sensibles détectées dans la migration:"
        for table in "${SENSITIVE_TABLES[@]}"; do
            # Vérifier si la table est dans la liste de migration
            for migrate_table in "${TABLES_TO_MIGRATE[@]}"; do
                if [ "$table" = "$migrate_table" ]; then
                    echo "   🔐 $table"
                fi
            done
        done
        echo ""
        read -p "Continuer avec ces tables sensibles ? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Migration annulée"
            exit 0
        fi
    fi
}

main_menu() {
    echo "🐍 MIGRATEUR DE DONNÉES DJANGO"
    echo "=============================="
    echo ""
    echo "Configuration chargée depuis: $CONFIG_FILE"
    echo "Tables configurées: ${#TABLES_TO_MIGRATE[@]}"
    echo "Séquences configurées: ${#SEQUENCES_TO_MIGRATE[@]}"
    echo ""
    echo "Base source: $PROD_HOST/$PROD_DB"
    echo "Base cible: $DEV_CONTAINER/$DEV_DB"
    echo ""
    echo "1) 🚀 Migration complète (export + restauration)"
    echo "2) 📦 Export uniquement"
    echo "3) 📊 Afficher les statistiques"
    echo "4) 🔧 Vérifier la configuration"
    echo "5) 🧪 Test des connexions"
    echo "6) ❌ Quitter"
    echo ""
}

test_connections() {
    print_status "🔍 Test des connexions..."
    
    # Test production
    if psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -c "SELECT version();" > /dev/null 2>&1; then
        print_success "✅ Connexion production OK"
    else
        print_error "❌ Connexion production FAILED"
        return 1
    fi
    
    # Test conteneur
    if docker ps --format "{{.Names}}" | grep -q "^$DEV_CONTAINER$"; then
        if docker exec "$DEV_CONTAINER" psql -U "$DEV_USER" -d "$DEV_DB" -c "SELECT 1;" > /dev/null 2>&1; then
            print_success "✅ Conteneur Docker OK"
        else
            print_error "❌ Base de données dans le conteneur inaccessible"
            return 1
        fi
    else
        print_error "❌ Conteneur '$DEV_CONTAINER' introuvable"
        return 1
    fi
    
    print_success "🎉 Toutes les connexions sont OK"
}

# ===============================================
# EXÉCUTION PRINCIPALE
# ===============================================

main() {
    while true; do
        main_menu
        read -p "Votre choix (1-6): " choice
        echo ""
        
        case $choice in
            1)
                check_sensitive_tables
                test_connections || exit 1
                dump_data
                restore_data
                show_stats
                print_success "🎉 Migration complète terminée!"
                break
                ;;
            2)
                check_sensitive_tables
                dump_data
                print_success "📦 Export terminé. Fichiers dans: $DUMP_DIR"
                break
                ;;
            3)
                show_stats
                echo ""
                read -p "Appuyez sur Entrée pour continuer..." 
                ;;
            4)
                validate_config
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            5)
                test_connections
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            6)
                print_status "Au revoir!"
                exit 0
                ;;
            *)
                print_error "Choix invalide"
                ;;
        esac
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