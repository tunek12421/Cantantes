-- Chat E2EE Database Schema
-- PostgreSQL 15+

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create custom types
CREATE TYPE user_role AS ENUM ('user', 'model', 'admin');
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'suspended', 'deleted');
CREATE TYPE device_platform AS ENUM ('web', 'ios', 'android');
CREATE TYPE media_type AS ENUM ('photo', 'video', 'audio');
CREATE TYPE verification_type AS ENUM ('sms', 'email');

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    username VARCHAR(50) UNIQUE,
    display_name VARCHAR(100),
    avatar_url TEXT,
    role user_role DEFAULT 'user',
    status user_status DEFAULT 'active',
    is_online BOOLEAN DEFAULT false,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Indexes for users
CREATE INDEX idx_users_phone ON users(phone_number);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_online ON users(is_online) WHERE is_online = true;

-- User verifications
CREATE TABLE user_verifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    type verification_type NOT NULL,
    code VARCHAR(6) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    attempts INTEGER DEFAULT 0,
    verified_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_verifications_user ON user_verifications(user_id);
CREATE INDEX idx_verifications_code ON user_verifications(code) WHERE verified_at IS NULL;

-- User devices for multi-device support
CREATE TABLE user_devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(100),
    platform device_platform NOT NULL,
    push_token TEXT,
    public_key TEXT NOT NULL, -- For E2EE
    last_active TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_devices_user ON user_devices(user_id);
CREATE INDEX idx_devices_device_id ON user_devices(device_id);

-- User sessions
CREATE TABLE user_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES user_devices(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) UNIQUE NOT NULL, -- SHA256 of JWT
    refresh_token_hash VARCHAR(64) UNIQUE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_used TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ip_address INET,
    user_agent TEXT
);

CREATE INDEX idx_sessions_user ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(token_hash);
CREATE INDEX idx_sessions_refresh ON user_sessions(refresh_token_hash);
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at);

-- Contacts/Connections between users
CREATE TABLE user_contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES users(id) ON DELETE CASCADE,
    nickname VARCHAR(100),
    blocked BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, contact_id)
);

CREATE INDEX idx_contacts_user ON user_contacts(user_id);
CREATE INDEX idx_contacts_contact ON user_contacts(contact_id);
CREATE INDEX idx_contacts_blocked ON user_contacts(user_id, blocked) WHERE blocked = true;

-- Model galleries
CREATE TABLE model_galleries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    total_size_bytes BIGINT DEFAULT 0,
    media_count INTEGER DEFAULT 0,
    settings JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_galleries_model ON model_galleries(model_id);

-- Gallery media items
CREATE TABLE gallery_media (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    gallery_id UUID REFERENCES model_galleries(id) ON DELETE CASCADE,
    type media_type NOT NULL,
    filename VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255),
    mime_type VARCHAR(100) NOT NULL,
    size_bytes BIGINT NOT NULL,
    width INTEGER,
    height INTEGER,
    duration_seconds INTEGER, -- For video/audio
    thumbnail_url TEXT,
    url TEXT NOT NULL, -- MinIO URL
    hash VARCHAR(64), -- SHA256 for deduplication
    is_public BOOLEAN DEFAULT true,
    upload_id VARCHAR(100), -- For resumable uploads
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_media_gallery ON gallery_media(gallery_id);
CREATE INDEX idx_media_type ON gallery_media(type);
CREATE INDEX idx_media_hash ON gallery_media(hash);
CREATE INDEX idx_media_created ON gallery_media(created_at DESC);

-- Message metadata (no content stored)
CREATE TABLE message_metadata (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id UUID REFERENCES users(id) ON DELETE SET NULL,
    recipient_id UUID REFERENCES users(id) ON DELETE SET NULL,
    sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    delivered_at TIMESTAMP WITH TIME ZONE,
    read_at TIMESTAMP WITH TIME ZONE,
    has_media BOOLEAN DEFAULT false,
    message_type VARCHAR(20) DEFAULT 'text'
);

CREATE INDEX idx_messages_sender ON message_metadata(sender_id);
CREATE INDEX idx_messages_recipient ON message_metadata(recipient_id);
CREATE INDEX idx_messages_sent ON message_metadata(sent_at DESC);

-- Analytics events (privacy-preserving)
CREATE TABLE analytics_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(50) NOT NULL,
    user_role user_role,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    properties JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_analytics_type ON analytics_events(event_type);
CREATE INDEX idx_analytics_created ON analytics_events(created_at DESC);

-- Rate limiting
CREATE TABLE rate_limits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    identifier VARCHAR(255) NOT NULL, -- IP or user_id
    endpoint VARCHAR(100) NOT NULL,
    requests INTEGER DEFAULT 1,
    window_start TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(identifier, endpoint, window_start)
);

CREATE INDEX idx_rate_limits_identifier ON rate_limits(identifier);
CREATE INDEX idx_rate_limits_window ON rate_limits(window_start);

-- Functions for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_galleries_updated_at BEFORE UPDATE ON model_galleries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Cleanup function for expired data
CREATE OR REPLACE FUNCTION cleanup_expired_data()
RETURNS void AS $$
BEGIN
    -- Delete expired verifications
    DELETE FROM user_verifications 
    WHERE expires_at < CURRENT_TIMESTAMP AND verified_at IS NULL;
    
    -- Delete expired sessions
    DELETE FROM user_sessions 
    WHERE expires_at < CURRENT_TIMESTAMP;
    
    -- Delete old rate limit entries
    DELETE FROM rate_limits 
    WHERE window_start < CURRENT_TIMESTAMP - INTERVAL '1 hour';
    
    -- Delete old analytics (keep 30 days)
    DELETE FROM analytics_events 
    WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- Initial data
INSERT INTO users (phone_number, username, display_name, role) 
VALUES ('+1234567890', 'admin', 'System Admin', 'admin')
ON CONFLICT DO NOTHING;