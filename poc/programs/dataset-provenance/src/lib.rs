use anchor_lang::prelude::*;

declare_id!("6nevEtv1X6KV8BprxJdD5qJSAPkdi2tym2zZPrvxeqF7");

#[program]
pub mod dataset_provenance {
    use super::*;

    /// Registra (ou sobrescreve) o hash + metadados de um dataset.
    pub fn store_dataset(
        ctx: Context<StoreDataset>,
        dataset_id: String,
        content_hash: [u8; 32],
        source: String,
        license: String,
        schema_version: u32,
    ) -> Result<()> {
        let record = &mut ctx.accounts.record;
        record.owner = ctx.accounts.authority.key();
        record.dataset_id = dataset_id;
        record.content_hash = content_hash;
        record.source = source;
        record.license = license;
        record.schema_version = schema_version;
        record.timestamp = Clock::get()?.unix_timestamp;
        record.bump = ctx.bumps.record;
        Ok(())
    }

    /// Atualiza apenas o hash (novo snapshot do mesmo dataset).
    pub fn update_dataset(
        ctx: Context<UpdateDataset>,
        _dataset_id: String,
        new_content_hash: [u8; 32],
    ) -> Result<()> {
        let record = &mut ctx.accounts.record;
        record.content_hash = new_content_hash;
        record.timestamp = Clock::get()?.unix_timestamp;
        Ok(())
    }

    /// Verifica se um hash bate com o registrado on-chain (read-only).
    pub fn verify_dataset(
        ctx: Context<VerifyDataset>,
        _dataset_id: String,
        content_hash: [u8; 32],
    ) -> Result<bool> {
        let record = &ctx.accounts.record;
        Ok(record.content_hash == content_hash)
    }
}

#[derive(Accounts)]
#[instruction(dataset_id: String)]
pub struct StoreDataset<'info> {
    #[account(
        init_if_needed,
        payer = authority,
        space = 8 + DatasetRecord::INIT_SPACE,
        seeds = [b"dataset", dataset_id.as_bytes()],
        bump
    )]
    pub record: Account<'info, DatasetRecord>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(dataset_id: String)]
pub struct UpdateDataset<'info> {
    #[account(
        mut,
        seeds = [b"dataset", dataset_id.as_bytes()],
        bump = record.bump,
        has_one = owner
    )]
    pub record: Account<'info, DatasetRecord>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(dataset_id: String)]
pub struct VerifyDataset<'info> {
    #[account(
        seeds = [b"dataset", dataset_id.as_bytes()],
        bump = record.bump
    )]
    pub record: Account<'info, DatasetRecord>,
}

#[account]
#[derive(InitSpace)]
pub struct DatasetRecord {
    pub owner: Pubkey,
    #[max_len(64)]
    pub dataset_id: String,
    pub content_hash: [u8; 32],
    #[max_len(128)]
    pub source: String,
    #[max_len(64)]
    pub license: String,
    pub schema_version: u32,
    pub timestamp: i64,
    pub bump: u8,
}
