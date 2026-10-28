. (Join-Path $PSScriptRoot 'PrivateTestCommon.ps1')

Describe 'New-PSDVClientCertificateCredential' {
    It 'creates an Azure.Identity client certificate credential from a runtime-generated certificate' {
        InModuleScope Dataverse {
            Import-PSDVAzureIdentityAssemblies
            $authContext = New-PSDVTestAuthContext -ParameterSetName 'ClientCertificate'
            $authContext.Certificate = New-PSDVTestCertificate

            $credential = New-PSDVClientCertificateCredential -AuthContext $authContext

            $credential.GetType().FullName | Should -Be 'Azure.Identity.ClientCertificateCredential'
        }
    }

    It 'loads a runtime-generated certificate file with a runtime-generated password' {
        InModuleScope Dataverse {
            Import-PSDVAzureIdentityAssemblies
            $certificateFile = $null
            try {
                $certificateFile = New-PSDVTestCertificateFile
                $authContext = New-PSDVTestAuthContext -ParameterSetName 'ClientCertificatePath'
                $authContext.CertificatePath = $certificateFile.Path
                $authContext.CertificatePassword = $certificateFile.Password

                $credential = New-PSDVClientCertificateCredential -AuthContext $authContext
                $credential.GetType().FullName | Should -Be 'Azure.Identity.ClientCertificateCredential'
            }
            finally {
                Clear-PSDVTestCertificateFile -CertificateFile $certificateFile
            }
        }
    }

    It 'throws when the certificate has no accessible private key' {
        InModuleScope Dataverse {
            $certificate = New-PSDVTestCertificate
            $publicOnlyBytes = $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            $publicOnlyCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($publicOnlyBytes)
            $authContext = New-PSDVTestAuthContext -ParameterSetName 'ClientCertificate'
            $authContext.Certificate = $publicOnlyCertificate

            { New-PSDVClientCertificateCredential -AuthContext $authContext } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }
    }
}