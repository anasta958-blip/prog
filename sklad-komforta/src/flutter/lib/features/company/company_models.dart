/// Реквизиты организации, общие для первичной настройки и рабочего пространства.
final class CompanyProfileDraft {
  CompanyProfileDraft({required this.organizationName});

  String organizationName;
  String? companyType;
  String? legalName;
  String? inn;
  String? kpp;
  String? ogrn;
  String? address;
  String? phone;
  String? email;

  factory CompanyProfileDraft.fromJson(Map<String, dynamic> json) =>
      CompanyProfileDraft(organizationName: json['organizationName'] as String)
        ..companyType = json['companyType'] as String?
        ..legalName = json['legalName'] as String?
        ..inn = json['inn'] as String?
        ..kpp = json['kpp'] as String?
        ..ogrn = json['ogrn'] as String?
        ..address = json['address'] as String?
        ..phone = json['phone'] as String?
        ..email = json['email'] as String?;

  Map<String, dynamic> toJson() => {
    'organizationName': organizationName,
    'companyType': companyType,
    'legalName': legalName,
    'inn': inn,
    'kpp': kpp,
    'ogrn': ogrn,
    'address': address,
    'phone': phone,
    'email': email,
  };
}
