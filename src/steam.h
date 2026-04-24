#ifndef STEAM_H
#define STEAM_H

#include <cstdint>

typedef unsigned char byte;
typedef int32_t int32;
typedef int64_t int64;
typedef uint8_t uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;
typedef uint64_t uint64;

typedef uint32 AppId_t;
typedef uint32 PackageId_t;
typedef uint32 PID_t;
typedef uint32 AccountID_t;
typedef uint32 HAuthTicket;

typedef int32 HSteamPipe;
typedef int32 HSteamUser;


constexpr AppId_t k_uAppIdInvalid = 0x0;
constexpr PackageId_t k_uPackageIdFreeSub = 0x0;
constexpr PackageId_t k_uPackageIdInvalid = 0xFFFFFFFF;
constexpr PackageId_t k_uPackageIdWallet = -2;
constexpr PackageId_t k_uPackageIdMicroTxn = -3;

enum class BillingType
{
	NoCost = 0,
	BillOnceOnly = 1,
	BillMonthly = 2,
	ProofOfPrepurchaseOnly = 3,
	GuestPass = 4,
	HardwarePromo = 5,
	Gift = 6,
	AutoGrant = 7,
	OEMTicket = 8,
	RecurringOption = 9,
	BillOnceOrCDKey = 10,
	Repurchaseable = 11,
	FreeOnDemand = 12,
	Rental = 13,
	CommercialLicense = 14,
	FreeCommercialLicense = 15,
	NumBillingTypes = 16

};

enum class ELicenseType
{
	NoLicense = 0,
	SinglePurchase = 1,
	SinglePurchaseLimitedUse = 2,
	RecurringCharge = 3,
	RecurringChargeLimitedUse = 4,
	RecurringChargeLimitedUseWithOverages = 5,
	RecurringOption = 6,
	LimitedUseDelayedActivation = 7

};

enum class EPackageStatus
{
	Available = 0,
	Preorder = 1,
	Unavailable = 2,
	Invalid = 3
};

enum class EAppReleaseState
{
	UnknownApp = 0,
	Unavailable = 1,
	Prerelease = 2,
	PreloadOnly = 3,
	Released = 4
};

enum class EGameIDType
{
	k_EGameIDTypeApp = 0,
	k_EGameIDTypeGameMod = 1,
	k_EGameIDTypeShortcut = 2,
	k_EGameIDTypeP2P = 3,
};

template<typename T>
struct CUtlVector {
	T* m_pMemory;
	uint32_t m_nAllocationCount;
	uint32_t m_nGrowSize;
	uint32_t m_Size;
};

struct PackageInfo
{
	AppId_t PackageId;
	int32 ChangeNumber;
	uint64 PICS_token;
	BillingType BillingType;
	ELicenseType LicenseType;
	EPackageStatus Status;
	byte SHA_1_Hash[20];
	void* pPackageInfoNodeBegin;
	void* pExtendNodeBegin;

	CUtlVector<AppId_t> AppIdVec;
	CUtlVector<AppId_t> DepotIdVec;
};

struct AppOwnership
{
	PackageId_t PackageId;
	EAppReleaseState ReleaseState; 
	AccountID_t SteamId32; 
	AppId_t MasterSubscriptionAppID; 
	uint32 TrialSeconds; 
	uint32 ExistInPackageNums; 
	char PurchaseCountryCode[4];
	uint32 TimeStamp;
	uint32 TimeExpire;
	int32 foo;
	EGameIDType GameIDType;
	int32 bar;
	int32 baz;

};

#endif // STEAM_H